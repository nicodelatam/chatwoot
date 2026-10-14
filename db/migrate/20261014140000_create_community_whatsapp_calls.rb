class CreateCommunityWhatsappCalls < ActiveRecord::Migration[7.1]
  def change
    create_table :community_whatsapp_calls do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :user_id
      t.string :session_id
      t.string :provider_call_id, null: false
      t.string :direction, null: false
      t.string :status, null: false, default: 'ringing'
      t.text :sdp_offer
      t.text :sdp_answer
      t.datetime :answered_at
      t.datetime :ended_at
      t.datetime :last_seen_at
      t.timestamps
    end

    add_index :community_whatsapp_calls, [:inbox_id, :provider_call_id], unique: true
    add_index :community_whatsapp_calls, :conversation_id
    add_index :community_whatsapp_calls, [:account_id, :user_id], unique: true,
              where: "user_id IS NOT NULL AND status IN ('ringing', 'connecting', 'active')", name: 'idx_community_calls_active_agent'
    add_index :community_whatsapp_calls, :conversation_id, unique: true,
              where: "status IN ('ringing', 'connecting', 'active')", name: 'idx_community_calls_active_conversation'
  end
end
