class CommunityCampaigns::StatusService
  def initialize(inbox, receipt)
    @inbox = inbox
    @receipt = receipt
  end

  def perform
    return unless @receipt[:id].is_a?(String) && @receipt[:id].present?

    deliveries = CommunityCampaignDelivery.where(account_id: @inbox.account_id, inbox_id: @inbox.id)
    delivery = deliveries.find_by(provider_message_id: @receipt[:id])
    tracking_id = @receipt[:biz_opaque_callback_data].to_s.match(/\Acommunity_campaign:(.+)\z/)&.captures&.first
    if delivery.nil? && tracking_id && tracking_id.bytesize <= 512
      signed_delivery = CommunityCampaignDelivery.find_signed(tracking_id, purpose: :community_campaign_receipt)
      delivery = deliveries.find_by(id: signed_delivery.id) if signed_delivery
    end
    delivery&.apply_receipt!(@receipt)
  rescue ArgumentError, KeyError, TypeError
    Rails.logger.warn '[COMMUNITY_CAMPAIGN] Invalid delivery receipt ignored'
  end
end
