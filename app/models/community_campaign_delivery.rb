class CommunityCampaignDelivery < ApplicationRecord
  STATUSES = %w[pending sent delivered read failed unconfirmed].freeze
  AWAITING_STATUSES = %w[pending sent unconfirmed].freeze
  SUCCESS_RANK = { 'sent' => 1, 'delivered' => 2, 'read' => 3 }.freeze
  CONFIRMED_REPLY_SOURCES = %w[button quote].freeze

  belongs_to :account
  belongs_to :campaign
  belongs_to :inbox
  belongs_to :contact, optional: true
  validates :status, inclusion: { in: STATUSES }

  def claim_send!
    with_lock do
      next false if attempted_at.present?

      update!(attempted_at: Time.current, status: 'unconfirmed')
      true
    end
  end

  def accept!(message_id)
    with_lock do
      raise ArgumentError, 'Provider message does not match delivery' if provider_message_id.present? && provider_message_id != message_id

      self.provider_message_id = message_id
      self.sent_at ||= Time.current
      self.status = 'sent' if AWAITING_STATUSES.include?(status)
      self.last_event_at ||= sent_at
      save!
    end
  end

  def fail!(code, message, uncertain: false)
    with_lock do
      next if %w[delivered read].include?(status)

      update!(status: uncertain ? 'unconfirmed' : 'failed', error_code: code, error_message: message.to_s.truncate(1000),
              failed_at: uncertain ? nil : Time.current, last_event_at: Time.current)
    end
  end

  # Keeps the first reply. A confirmed reply replaces an earlier probable one, never the reverse.
  def record_reply!(message, source)
    with_lock do
      next if replied_at.present? && (CONFIRMED_REPLY_SOURCES.include?(reply_source) || source == 'window')

      update!(replied_at: replied_at || message.created_at, reply_message_id: message.id,
              reply_conversation_id: message.conversation_id, reply_source: source)
    end
  end

  def apply_receipt!(receipt)
    next_status = receipt.fetch(:status)
    return unless SUCCESS_RANK.key?(next_status) || next_status == 'failed'

    event_at = Time.zone.at(Integer(receipt.fetch(:timestamp), 10))
    with_lock do
      next if provider_message_id.present? && provider_message_id != receipt[:id]

      self.provider_message_id ||= receipt[:id]
      if next_status == 'failed'
        next if %w[delivered read].include?(status)

        error = receipt[:errors]&.first || {}
        self.status = 'failed'
        self.failed_at ||= event_at
        self.error_code = error[:code]&.to_s
        self.error_message = (error.dig(:error_data, :details).presence || error[:message].presence || error[:title]).to_s.truncate(1000)
      else
        # A read receipt also proves delivery, even when Meta omits the intermediate receipt.
        self.sent_at = [sent_at, event_at].compact.min
        self.delivered_at = [delivered_at, event_at].compact.min if %w[delivered read].include?(next_status)
        self.read_at = [read_at, event_at].compact.min if next_status == 'read'
        if SUCCESS_RANK.fetch(next_status) > SUCCESS_RANK.fetch(status, 0) && (status != 'failed' || next_status != 'sent')
          self.status = next_status
          self.failed_at = self.error_code = self.error_message = nil
        end
      end
      self.last_event_at = [last_event_at, event_at].compact.max
      save!
    end
  end

  def self.metrics_by_campaign
    metrics = Hash.new { |hash, key| hash[key] = CommunityCampaignReport.empty_metrics }
    group(:campaign_id, :status).count.each do |(campaign_id, state), count|
      metrics[campaign_id][:total] += count
      metrics[campaign_id][:failed] += count if state == 'failed'
      metrics[campaign_id][:pending] += count if AWAITING_STATUSES.include?(state)
      metrics[campaign_id][:unconfirmed] += count if state == 'unconfirmed'
    end
    %i[sent delivered read].each do |state|
      where.not("#{state}_at" => nil).group(:campaign_id).count.each { |id, count| metrics[id][state] = count }
    end
    where(historical: true).group(:campaign_id).count.each { |id, count| metrics[id][:historical] = count }
    where.not(replied_at: nil).group(:campaign_id).count.each { |id, count| metrics[id][:replied] = count }
    where(reply_source: CONFIRMED_REPLY_SOURCES).group(:campaign_id).count.each { |id, count| metrics[id][:replied_confirmed] = count }
    metrics
  end

  def self.daily_activity(from:, to:, zone:)
    days = (from..to).to_h { |day| [day.iso8601, { date: day.iso8601, sent: 0, delivered: 0, read: 0, failed: 0 }] }
    in_batches(of: 1000) do |batch|
      batch.pluck(:sent_at, :delivered_at, :read_at, :failed_at).each do |timestamps|
        %i[sent delivered read failed].zip(timestamps).each do |state, timestamp|
          next unless timestamp

          date = timestamp.in_time_zone(zone).to_date.iso8601
          days[date][state] += 1 if days.key?(date)
        end
      end
    end
    days.values
  end

  def self.matching_contact(query)
    return all if query.blank?

    pattern = "%#{sanitize_sql_like(query)}%"
    columns = Contact.arel_table
    where(contact_id: Contact.where(columns[:name].matches(pattern).or(columns[:phone_number].matches(pattern))).select(:id))
  end

  def self.filtered_by_status(value)
    return all if value.blank? || value == 'all'
    return where.not(sent_at: nil) if value == 'accepted'
    return where.not(delivered_at: nil) if value == 'delivered_all'
    return where.not(replied_at: nil) if value == 'replied'

    where(status: value == 'awaiting' ? AWAITING_STATUSES : value)
  end

  def statistics_payload
    { id: id, campaign_id: campaign.display_id, campaign_title: campaign.title, status: status,
      contact: { id: contact_id, name: contact&.name, phone_number: contact&.phone_number },
      sent_at: sent_at, delivered_at: delivered_at, read_at: read_at, failed_at: failed_at,
      error_code: error_code, error_message: error_message, last_event_at: last_event_at, historical: historical,
      replied_at: replied_at, reply_source: reply_source }
  end
end
