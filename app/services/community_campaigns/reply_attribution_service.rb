# Attributes an incoming WhatsApp Cloud message to the community campaign it answers.
#
# A Click-to-WhatsApp ad referral always wins and is never counted for a campaign. A quote of the
# campaign template or a tap on one of its quick-reply buttons is confirmed. Otherwise the first
# message written within 24 hours of the latest successful send, with no conversation activity in
# between, is only probable.
class CommunityCampaigns::ReplyAttributionService
  REPLY_WINDOW = 24.hours
  SUCCESSFUL_STATUSES = %w[sent delivered read].freeze

  Result = Struct.new(:delivery, :source) do
    def content_attributes
      { campaign_id: delivery.campaign.display_id, title: delivery.campaign.title,
        confidence: CommunityCampaignDelivery::CONFIRMED_REPLY_SOURCES.include?(source) ? 'confirmed' : 'probable',
        source: source, sent_at: delivery.sent_at.iso8601 }
    end
  end

  pattr_initialize [:inbox!, :contact!, :message!]

  def perform
    return if message[:referral].present?

    confirmed_attribution || probable_attribution
  end

  private

  def confirmed_attribution
    context_id = message.dig(:context, :id)
    return if context_id.blank?

    delivery = deliveries.find_by(provider_message_id: context_id) || delivery_matching_token(context_id)
    Result.new(delivery, message[:type] == 'button' ? 'button' : 'quote') if delivery
  end

  # Phone-scoped and BSUID-scoped WAMIDs of the same message can differ while sharing one token.
  def delivery_matching_token(context_id)
    token = Whatsapp::InReplyToMessageFinder.message_token(context_id)
    return if token.blank?

    contact_deliveries.where.not(provider_message_id: nil).find do |delivery|
      Whatsapp::InReplyToMessageFinder.message_token(delivery.provider_message_id) == token
    end
  end

  def probable_attribution
    delivery = contact_deliveries.where.not(sent_at: nil).order(sent_at: :desc).first
    return unless delivery && delivery.replied_at.nil? && SUCCESSFUL_STATUSES.include?(delivery.status)
    return if delivery.sent_at < received_at - REPLY_WINDOW
    return if conversation_activity_since?(delivery.sent_at)

    Result.new(delivery, 'window')
  end

  def conversation_activity_since?(time)
    Message.where(conversation_id: contact.conversations.where(inbox_id: inbox.id).select(:id), private: false,
                  message_type: %i[incoming outgoing], created_at: time..).exists?
  end

  def received_at
    Time.zone.at(Integer(message[:timestamp], 10))
  end

  def deliveries
    CommunityCampaignDelivery.where(inbox_id: inbox.id).includes(:campaign)
  end

  def contact_deliveries
    deliveries.where(contact_id: contact.id)
  end
end
