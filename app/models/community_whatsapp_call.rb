class CommunityWhatsappCall < ApplicationRecord
  ACTIVE_STATUSES = %w[ringing connecting active].freeze
  TERMINAL_STATUSES = %w[completed rejected missed failed].freeze

  belongs_to :account
  belongs_to :inbox
  belongs_to :conversation
  belongs_to :user, optional: true

  validates :provider_call_id, presence: true, uniqueness: { scope: :inbox_id }
  validates :direction, inclusion: { in: %w[incoming outgoing] }
  validates :status, inclusion: { in: ACTIVE_STATUSES + TERMINAL_STATUSES }

  scope :ongoing, -> { where(status: ACTIVE_STATUSES) }

  def ongoing?
    ACTIVE_STATUSES.include?(status)
  end

  def finish!(final_status)
    return unless ongoing?

    update!(status: final_status, ended_at: Time.current, sdp_offer: nil, sdp_answer: nil)
    conversation.messages.create!(
      account_id: account_id, inbox_id: inbox_id, message_type: :activity,
      content: I18n.t("community_calling.#{final_status}", direction: I18n.t("community_calling.#{direction}")),
      content_attributes: { community_whatsapp_call_id: id }
    )
  end

  def dashboard_payload(include_session: false)
    payload = slice(:id, :provider_call_id, :inbox_id, :direction, :status, :user_id)
    payload.merge!(conversation_id: conversation.display_id, contact_name: conversation.contact.name)
    payload.merge!(slice(:sdp_offer, :sdp_answer)) if include_session
    payload
  end
end
