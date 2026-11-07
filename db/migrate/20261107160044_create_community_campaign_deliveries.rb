class CreateCommunityCampaignDeliveries < ActiveRecord::Migration[7.2]
  def change
    create_table :community_campaign_reports do |t|
      t.bigint :account_id, null: false
      t.bigint :campaign_id, null: false
      t.bigint :inbox_id, null: false
      t.jsonb :audience_labels, null: false, default: []
      t.integer :audience_size, null: false, default: 0
      t.boolean :historical, null: false, default: false
      t.boolean :snapshot_complete, null: false, default: false
      t.datetime :tracking_started_at
      t.timestamps
    end
    add_index :community_campaign_reports, :campaign_id, unique: true
    add_index :community_campaign_reports, :account_id

    create_table :community_campaign_deliveries do |t|
      t.bigint :account_id, null: false
      t.bigint :campaign_id, null: false
      t.bigint :inbox_id, null: false
      t.bigint :contact_id
      t.string :provider_message_id
      t.string :status, null: false, default: 'pending'
      t.string :error_code
      t.text :error_message
      t.boolean :historical, null: false, default: false
      t.datetime :attempted_at
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :read_at
      t.datetime :failed_at
      t.datetime :last_event_at
      t.timestamps
    end
    add_index :community_campaign_deliveries, [:campaign_id, :contact_id], unique: true, name: 'idx_community_deliveries_contact'
    add_index :community_campaign_deliveries, [:inbox_id, :provider_message_id], unique: true, name: 'idx_community_deliveries_provider'
    add_index :community_campaign_deliveries, [:account_id, :campaign_id, :status], name: 'idx_community_deliveries_report'
    add_index :community_campaign_deliveries, :contact_id
  end
end
