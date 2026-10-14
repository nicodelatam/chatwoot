class CommunityCalling::WebhookService
  def initialize(channel, value)
    @channel = channel
    @value = value
  end

  def perform
    Array(@value[:calls]).each { |event| process_call(event) }
    Array(@value[:statuses]).each { |event| process_status(event) if event[:type] == 'call' }
  end

  private

  def process_call(event)
    call = outgoing_call_event?(event) ? find_outgoing(event) : find_or_build_incoming(event)
    call.with_lock { process_call_event(call, event) }
  end

  def outgoing_call_event?(event)
    event[:direction] == 'BUSINESS_INITIATED' || event.dig(:session, :sdp_type) == 'answer'
  end

  def find_or_build_incoming(event)
    calls.find_by(provider_call_id: event.fetch(:id)) || build_incoming(event)
  end

  def process_call_event(call, event)
    return unless call.ongoing?

    case event[:event]
    when 'terminate'
      call.finish!(termination_status(call, event))
    when 'connect'
      call.update!(sdp_answer: event.fetch(:session).fetch(:sdp)) if event.dig(:session, :sdp_type) == 'answer'
    end
  end

  def termination_status(call, event)
    return 'failed' if event[:status] == 'FAILED'

    call.answered_at ? 'completed' : 'missed'
  end

  def process_status(event)
    call = find_outgoing(event)
    call.with_lock do
      next unless call.ongoing?

      case event[:status]
      when 'ACCEPTED'
        call.update!(status: 'active', answered_at: Time.current)
      when 'REJECTED'
        call.finish!('rejected')
      end
    end
  end

  def calls
    CommunityWhatsappCall.where(inbox_id: @channel.inbox.id)
  end

  def find_outgoing(event)
    existing = calls.find_by(provider_call_id: event.fetch(:id))
    return existing if existing

    callback_id = event[:biz_opaque_callback_data]
    raise ActiveRecord::RecordNotFound unless callback_id.is_a?(String) && callback_id.match?(/\A\d+\z/)

    call = calls.where(direction: 'outgoing').find(callback_id)
    call.with_lock do
      raise ActiveRecord::RecordNotFound unless call.provider_call_id.start_with?('pending:') || call.provider_call_id == event[:id]

      call.update!(provider_call_id: event.fetch(:id))
    end
    call
  end

  def build_incoming(event)
    contact_inbox = incoming_contact_inbox(event)
    conversation = find_or_create_conversation(contact_inbox)
    call = calls.create!(account: @channel.account, conversation: conversation, direction: 'incoming',
                         provider_call_id: event.fetch(:id), sdp_offer: event.dig(:session, :sdp))
    CommunityCalling::WatchdogJob.set(wait: 30.seconds).perform_later(call.id)
    if contact_inbox.contact.blocked?
      CommunityCalling::MetaClient.new(@channel).control(call, 'reject')
      call.finish!('rejected')
    end
    call
  rescue ActiveRecord::RecordNotUnique
    # Duplicate webhook deliveries share the provider ID; the first row remains authoritative.
    calls.find_by!(provider_call_id: event.fetch(:id))
  end

  def incoming_contact_inbox(event)
    contact = matching_contact(event)
    source_id = contact_source_id(event, contact)
    raise ArgumentError, 'Missing WhatsApp calling contact identity' unless source_id

    phone = event[:from].presence || contact[:wa_id].presence
    ContactInboxWithContactBuilder.new(
      inbox: @channel.inbox, source_id: source_id,
      contact_attributes: {
        name: contact.dig(:profile, :name) || phone || source_id,
        phone_number: phone && "+#{phone.delete_prefix('+')}"
      }
    ).perform
  end

  def matching_contact(event)
    Array(@value[:contacts]).find do |candidate|
      [candidate[:wa_id], candidate[:user_id], candidate[:parent_user_id]].compact.intersect?(
        [event[:from], event[:from_user_id], event[:from_parent_user_id]].compact
      )
    end || {}
  end

  def contact_source_id(event, contact)
    [
      event[:from_parent_user_id], contact[:parent_user_id], event[:from_user_id], contact[:user_id], event[:from]
    ].compact_blank.first
  end

  def find_or_create_conversation(contact_inbox)
    contact_inbox.conversations.where.not(status: :resolved).order(:id).last ||
      Conversation.create!(
        account: @channel.account, inbox: @channel.inbox, contact: contact_inbox.contact,
        contact_inbox: contact_inbox
      )
  end
end
