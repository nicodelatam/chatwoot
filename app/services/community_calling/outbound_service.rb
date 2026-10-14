class CommunityCalling::OutboundService
  def initialize(conversation, user, session_id:, sdp:)
    @conversation = conversation
    @user = user
    @session_id = session_id
    @sdp = sdp
  end

  def perform
    call = reserve_call
    # Reserve the agent/conversation before contacting Meta so concurrent clicks cannot place two calls.
    CommunityCalling::WatchdogJob.set(wait: 30.seconds).perform_later(call.id)
    meta = CommunityCalling::MetaClient.new(@conversation.inbox.channel)
    result = meta.connect(@conversation.contact_inbox.source_id, @sdp, call.id.to_s)
    call.update!(provider_call_id: result.fetch('calls').first.fetch('id'))
    call
  rescue CustomExceptions::CommunityCallingError => e
    # A timeout may follow a successful connect at Meta. Keep the reservation for reconciliation and cleanup.
    call&.with_lock { call.finish!('failed') } unless e.code == 'meta_unavailable'
    raise
  end

  private

  def reserve_call
    CommunityWhatsappCall.create!(
      account: @conversation.account, inbox: @conversation.inbox, conversation: @conversation, user: @user,
      session_id: @session_id, direction: 'outgoing', provider_call_id: "pending:#{SecureRandom.uuid}",
      sdp_offer: @sdp, last_seen_at: Time.current
    )
  end
end
