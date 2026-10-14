class CommunityCalling::WebhookJob < MutexApplicationJob
  queue_as :default
  self.log_arguments = false
  retry_on ActiveRecord::RecordNotFound, wait: 2.seconds, attempts: 10
  retry_on LockAcquisitionError, wait: 2.seconds, attempts: 20

  def perform(channel_id, value)
    channel = Channel::Whatsapp.find(channel_id)
    return unless channel.account.active? && channel.provider_config['community_calling_enabled'] == true

    events = value.with_indifferent_access
    sender_id = Array(events[:calls]).filter_map { |call| call[:from_parent_user_id] || call[:from_user_id] || call[:from] }.first
    return CommunityCalling::WebhookService.new(channel, events).perform if sender_id.blank?

    key = format(::Redis::Alfred::WHATSAPP_MESSAGE_MUTEX, inbox_id: channel.inbox.id, sender_id: sender_id)
    with_lock(key, 30.seconds) { CommunityCalling::WebhookService.new(channel, events).perform }
  end
end
