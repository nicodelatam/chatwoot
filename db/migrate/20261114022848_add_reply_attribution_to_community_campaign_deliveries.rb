class AddReplyAttributionToCommunityCampaignDeliveries < ActiveRecord::Migration[7.2]
  def change
    add_column :community_campaign_deliveries, :replied_at, :datetime
    add_column :community_campaign_deliveries, :reply_message_id, :bigint
    add_column :community_campaign_deliveries, :reply_conversation_id, :bigint
    add_column :community_campaign_deliveries, :reply_source, :string
  end
end
