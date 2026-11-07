# A read-only adapter for the user's pre-existing delivery records; no Enterprise code is loaded.
class CommunityCampaigns::HistoricalDelivery < ActiveRecord::Base
  self.table_name = 'campaign_recipients'

  def readonly?
    true
  end

  def community_attributes
    state = if read_at then 'read'
            elsif delivered_at then 'delivered'
            elsif failed_at then 'failed'
            elsif source_id.present? then 'sent'
            else 'unconfirmed'
            end
    { account_id: account_id, campaign_id: campaign_id, inbox_id: inbox_id, contact_id: contact_id,
      provider_message_id: source_id.presence, status: state, historical: true,
      error_code: error_code, error_message: error_message.presence || error_title,
      attempted_at: send_attempted_at || created_at, sent_at: sent_at || delivered_at || read_at,
      delivered_at: delivered_at || read_at, read_at: read_at, failed_at: failed_at,
      last_event_at: updated_at, created_at: created_at, updated_at: updated_at }
  end
end
