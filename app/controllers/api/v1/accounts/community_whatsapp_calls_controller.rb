class Api::V1::Accounts::CommunityWhatsappCallsController < Api::V1::Accounts::BaseController
  before_action :ensure_human_user
  before_action :set_call, only: %i[show pre_accept accept reject terminate]
  before_action :set_conversation, only: %i[create permission request_permission]

  rescue_from CustomExceptions::CommunityCallingError do |error|
    render json: { error: error.message, code: error.code }, status: :unprocessable_entity
  end
  rescue_from ActiveRecord::RecordNotUnique do
    render json: {
      error: 'An agent or this conversation already has a call in progress.', code: 'call_busy'
    }, status: :conflict
  end

  def index
    inboxes = current_user.assigned_inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel)
    supported = inboxes.select { |inbox| inbox.channel.provider == 'whatsapp_cloud' }
    calls = CommunityWhatsappCall.ongoing.where(account_id: Current.account.id, inbox_id: supported.map(&:id))
    calls = calls.where('user_id IS NULL OR (user_id = ? AND session_id = ?)', current_user.id, params[:session_id])
    calls = calls.includes(conversation: :contact)
    render json: { calls: calls.map(&:dashboard_payload), inboxes: supported.map { |inbox| inbox_payload(inbox) } }
  end

  def show
    if @call.user_id == current_user.id && @call.session_id == params[:session_id] && @call.ongoing? &&
       (@call.last_seen_at.nil? || @call.last_seen_at < 10.seconds.ago)
      @call.update!(last_seen_at: Time.current)
    end
    render json: @call.dashboard_payload(include_session: @call.user_id.nil? || owned_session?)
  end

  def configure
    inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize inbox, :update?
    channel = inbox.channel
    raise CustomExceptions::CommunityCallingError, 'Choose a WhatsApp Cloud API inbox.' unless inbox.whatsapp? && channel.provider == 'whatsapp_cloud'
    raise CustomExceptions::CommunityCallingError, 'enabled must be a boolean.' unless [true, false].include?(params[:enabled])

    channel.with_lock do
      CommunityCalling::ConfigurationService.new(channel).perform(params[:enabled])
    end
    render json: inbox_payload(inbox)
  end

  def permission
    render json: permission_payload
  end

  def request_permission
    state = permission_payload
    unless state[:can_request]
      raise CustomExceptions::CommunityCallingError,
            'Meta does not allow another permission request yet. Wait for the contact to respond.'
    end

    unless @conversation.can_reply?
      message = 'Outside the 24-hour service window, send an approved call-permission template ' \
                'or ask the contact to allow calls in your WhatsApp business profile.'
      raise CustomExceptions::CommunityCallingError, message
    end

    result = meta.request_permission(@conversation.contact_inbox.source_id)
    @conversation.messages.create!(
      account_id: Current.account.id, inbox_id: @conversation.inbox_id, sender: current_user,
      message_type: :activity, content: I18n.t('community_calling.permission_sent'),
      content_attributes: { whatsapp_permission_message_id: result.fetch('messages').first.fetch('id') }
    )
    render json: { status: 'permission_requested' }
  end

  def create
    validate_session!
    validate_sdp!(:sdp_offer)
    ensure_call_permission!
    call = CommunityCalling::OutboundService.new(@conversation, current_user, session_id: params[:session_id], sdp: params[:sdp_offer]).perform
    render json: call.dashboard_payload, status: :created
  end

  def pre_accept
    validate_session!
    validate_sdp!(:sdp_answer)
    @call.with_lock do
      unless @call.direction == 'incoming' && @call.status == 'ringing'
        raise CustomExceptions::CommunityCallingError, 'This call is no longer ringing.'
      end

      @call.update!(
        user: current_user, session_id: params[:session_id], status: 'connecting',
        sdp_answer: params[:sdp_answer], last_seen_at: Time.current
      )
      meta.control(@call, 'pre_accept', sdp: params[:sdp_answer])
    end
    render json: @call.dashboard_payload
  end

  def accept
    @call.with_lock do
      ensure_owned_session!
      raise CustomExceptions::CommunityCallingError, 'This call is not waiting for acceptance.' unless @call.status == 'connecting'

      meta.control(@call, 'accept', sdp: @call.sdp_answer)
      @call.update!(status: 'active', answered_at: Time.current, last_seen_at: Time.current)
    end
    render json: @call.dashboard_payload
  end

  def reject
    @call.with_lock do
      unless @call.direction == 'incoming' && @call.status == 'ringing'
        raise CustomExceptions::CommunityCallingError, 'This call is no longer ringing.'
      end

      meta.control(@call, 'reject')
      @call.finish!('rejected')
    end
    render json: @call.dashboard_payload
  end

  def terminate
    @call.with_lock do
      ensure_owned_session!
      if @call.ongoing?
        meta.control(@call, 'terminate') unless @call.provider_call_id.start_with?('pending:')
        @call.finish!(@call.answered_at ? 'completed' : 'missed')
      end
    end
    render json: @call.dashboard_payload
  end

  private

  def ensure_call_permission!
    return if permission_payload[:can_call]

    raise CustomExceptions::CommunityCallingError.new('Call permission required.', 'permission_required')
  end

  def ensure_human_user
    raise Pundit::NotAuthorizedError unless current_user.is_a?(User)
  end

  def inbox_payload(inbox)
    { id: inbox.id, name: inbox.name, enabled: inbox.channel.provider_config['community_calling_enabled'] == true,
      can_manage: Current.account_user.administrator? }
  end

  def set_call
    @call = CommunityWhatsappCall.where(account_id: Current.account.id).find(params[:id])
    authorize @call.inbox, :show?
    @channel = @call.inbox.channel
  end

  def set_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
    authorize @conversation.inbox, :show?
    @channel = @conversation.inbox.channel
    unless @conversation.inbox.whatsapp? && @channel.provider == 'whatsapp_cloud' &&
           @channel.provider_config['community_calling_enabled'] == true
      raise CustomExceptions::CommunityCallingError, 'Enable community calling on this WhatsApp Cloud API inbox first.'
    end

    raise CustomExceptions::CommunityCallingError, 'Calling is unavailable for blocked contacts.' if @conversation.contact.blocked?
  end

  def meta
    @meta ||= CommunityCalling::MetaClient.new(@channel)
  end

  def permission_payload
    response = meta.permission(@conversation.contact_inbox.source_id)
    actions = response.fetch('actions').index_by { |action| action.fetch('action_name') }
    { can_call: actions.fetch('start_call').fetch('can_perform_action'),
      can_request: actions.fetch('send_call_permission_request').fetch('can_perform_action'),
      status: response.fetch('permission').fetch('status') }
  end

  def owned_session?
    @call.user_id == current_user.id && @call.session_id == params[:session_id]
  end

  def ensure_owned_session!
    validate_session!
    raise Pundit::NotAuthorizedError unless owned_session?
  end

  def validate_session!
    uuid_pattern = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    return if params[:session_id].is_a?(String) && params[:session_id].match?(uuid_pattern)

    raise CustomExceptions::CommunityCallingError, 'session_id must be a UUID.'
  end

  def validate_sdp!(key)
    value = params[key]
    valid_sdp = value.is_a?(String) && value.bytesize <= 20_000 && value.start_with?('v=0') &&
                value.include?('m=audio') && value.include?('a=fingerprint:')
    return if valid_sdp

    raise CustomExceptions::CommunityCallingError, 'Provide a valid audio WebRTC session description.'
  end
end
