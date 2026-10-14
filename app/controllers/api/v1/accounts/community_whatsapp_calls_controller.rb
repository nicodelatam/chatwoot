class Api::V1::Accounts::CommunityWhatsappCallsController < Api::V1::Accounts::BaseController
  before_action :ensure_human_user
  before_action :set_call, only: %i[show pre_accept accept reject terminate]
  before_action :set_conversation, only: %i[create permission request_permission]

  rescue_from CommunityCallingError do |error|
    render json: { error: error.message, code: error.code }, status: :unprocessable_entity
  end
  rescue_from ActiveRecord::RecordNotUnique do
    render json: { error: 'An agent or this conversation already has a call in progress.', code: 'call_busy' }, status: :conflict
  end

  def index
    inboxes = current_user.assigned_inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel)
    supported = inboxes.select { |inbox| inbox.channel.provider == 'whatsapp_cloud' }
    calls = CommunityWhatsappCall.ongoing.where(account_id: Current.account.id, inbox_id: supported.map(&:id))
                                .where('user_id IS NULL OR (user_id = ? AND session_id = ?)', current_user.id, params[:session_id])
                                .includes(conversation: :contact)
    render json: { calls: calls.map(&:dashboard_payload), inboxes: supported.map { |inbox| inbox_payload(inbox) } }
  end

  def show
    if @call.user_id == current_user.id && @call.session_id == params[:session_id] && @call.ongoing?
      @call.update!(last_seen_at: Time.current) if @call.last_seen_at.nil? || @call.last_seen_at < 10.seconds.ago
    end
    render json: @call.dashboard_payload(include_session: @call.user_id.nil? || owned_session?)
  end

  def configure
    inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize inbox, :update?
    channel = inbox.channel
    raise CommunityCallingError, 'Choose a WhatsApp Cloud API inbox.' unless inbox.whatsapp? && channel.provider == 'whatsapp_cloud'
    raise CommunityCallingError, 'enabled must be a boolean.' unless [true, false].include?(params[:enabled])

    channel.with_lock do
      configure_channel(channel)
    end
    render json: inbox_payload(inbox)
  end

  def permission
    render json: permission_payload
  end

  def request_permission
    state = permission_payload
    raise CommunityCallingError, 'Meta does not allow another permission request yet. Wait for the contact to respond.' unless state[:can_request]
    unless @conversation.can_reply?
      raise CommunityCallingError, 'Outside the 24-hour service window, send an approved call-permission template or ask the contact to allow calls in your WhatsApp business profile.'
    end

    result = meta.request_permission(@conversation.contact_inbox.source_id)
    @conversation.messages.create!(account_id: Current.account.id, inbox_id: @conversation.inbox_id, sender: current_user,
                                   message_type: :activity, content: I18n.t('community_calling.permission_sent'),
                                   content_attributes: { whatsapp_permission_message_id: result.fetch('messages').first.fetch('id') })
    render json: { status: 'permission_requested' }
  end

  def create
    validate_session!
    validate_sdp!(:sdp_offer)
    raise CommunityCallingError.new('Call permission required.', 'permission_required') unless permission_payload[:can_call]

    call = CommunityWhatsappCall.create!(
      account: Current.account, inbox: @conversation.inbox, conversation: @conversation, user: current_user,
      session_id: params[:session_id], direction: 'outgoing', provider_call_id: "pending:#{SecureRandom.uuid}",
      sdp_offer: params[:sdp_offer], last_seen_at: Time.current
    )
    # Reserve the agent/conversation before contacting Meta so concurrent clicks cannot place two calls.
    CommunityCalling::WatchdogJob.set(wait: 30.seconds).perform_later(call.id)
    result = meta.connect(@conversation.contact_inbox.source_id, params[:sdp_offer], call.id.to_s)
    call.update!(provider_call_id: result.fetch('calls').first.fetch('id'))
    render json: call.dashboard_payload, status: :created
  rescue CommunityCallingError => error
    # A timeout may follow a successful connect at Meta. Keep the reservation for webhook reconciliation and cleanup.
    call&.with_lock { call.finish!('failed') } unless error.code == 'meta_unavailable'
    raise
  end

  def pre_accept
    validate_session!
    validate_sdp!(:sdp_answer)
    @call.with_lock do
      raise CommunityCallingError, 'This call is no longer ringing.' unless @call.direction == 'incoming' && @call.status == 'ringing'

      @call.update!(user: current_user, session_id: params[:session_id], status: 'connecting', sdp_answer: params[:sdp_answer], last_seen_at: Time.current)
      meta.control(@call, 'pre_accept', sdp: params[:sdp_answer])
    end
    render json: @call.dashboard_payload
  end

  def accept
    @call.with_lock do
      ensure_owned_session!
      raise CommunityCallingError, 'This call is not waiting for acceptance.' unless @call.status == 'connecting'

      meta.control(@call, 'accept', sdp: @call.sdp_answer)
      @call.update!(status: 'active', answered_at: Time.current, last_seen_at: Time.current)
    end
    render json: @call.dashboard_payload
  end

  def reject
    @call.with_lock do
      raise CommunityCallingError, 'This call is no longer ringing.' unless @call.direction == 'incoming' && @call.status == 'ringing'

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
    unless @conversation.inbox.whatsapp? && @channel.provider == 'whatsapp_cloud' && @channel.provider_config['community_calling_enabled'] == true
      raise CommunityCallingError, 'Enable community calling on this WhatsApp Cloud API inbox first.'
    end
    raise CommunityCallingError, 'Calling is unavailable for blocked contacts.' if @conversation.contact.blocked?
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

  def configure_channel(channel)
    if params[:enabled]
      raise CommunityCallingError, 'Disable Enterprise calling on this inbox before enabling community calling.' if channel.provider_config['calling_enabled']
      secret = MetaTokenVerifyConcern::CHANNEL_APP_SECRET_KEYS.any? { |key| channel.provider_config[key].present? }
      raise CommunityCallingError, 'Configure the Meta app secret before enabling calling so incoming webhooks can be verified.' unless secret || GlobalConfigService.load('WHATSAPP_APP_SECRET', nil).present?

      CommunityCalling::MetaClient.new(channel).enable
    elsif CommunityWhatsappCall.ongoing.exists?(inbox_id: channel.inbox.id)
      raise CommunityCallingError, 'End the calls in this inbox before disabling calling.'
    elsif channel.provider_config['community_calling_enabled'] == true
      CommunityCalling::MetaClient.new(channel).disable
    end
    channel.provider_config = channel.provider_config.merge('community_calling_enabled' => params[:enabled])
    # The pending flag is visible to the shared WABA subscription setup before it is persisted.
    Whatsapp::WebhookSetupService.new(channel).register_callback
    channel.save!(validate: false)
  end

  def owned_session?
    @call.user_id == current_user.id && @call.session_id == params[:session_id]
  end

  def ensure_owned_session!
    validate_session!
    raise Pundit::NotAuthorizedError unless owned_session?
  end

  def validate_session!
    return if params[:session_id].is_a?(String) && params[:session_id].match?(/\A[0-9a-f-]{36}\z/i)

    raise CommunityCallingError, 'session_id must be a UUID.'
  end

  def validate_sdp!(key)
    value = params[key]
    return if value.is_a?(String) && value.bytesize <= 20_000 && value.start_with?('v=0') && value.include?('m=audio') && value.include?('a=fingerprint:')

    raise CommunityCallingError, 'Provide a valid audio WebRTC session description.'
  end
end
