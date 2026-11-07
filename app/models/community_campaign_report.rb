class CommunityCampaignReport < ApplicationRecord
  belongs_to :account
  belongs_to :campaign
  belongs_to :inbox
  has_many :deliveries, class_name: 'CommunityCampaignDelivery', primary_key: :campaign_id, foreign_key: :campaign_id

  def self.prepare!(campaign)
    report = create_or_find_by!(campaign_id: campaign.id) { |record| record.account = campaign.account; record.inbox = campaign.inbox }
    campaign.account.with_lock do
      report.with_lock do
        next if report.snapshot_complete?

        selection = CommunityCampaigns::Audience.new(campaign)
        labels = selection.labels
        ids = selection.contacts.pluck(:id)
        now = Time.current
        ids.each_slice(1000) do |batch|
          rows = batch.map do |contact_id|
            { account_id: campaign.account_id, inbox_id: campaign.inbox_id, campaign_id: campaign.id,
              contact_id: contact_id, status: 'pending', created_at: now, updated_at: now }
          end
          CommunityCampaignDelivery.insert_all(rows, unique_by: :idx_community_deliveries_contact)
        end
        report.update!(audience_labels: labels, audience_size: ids.size, tracking_started_at: now, snapshot_complete: true)
      end
    end
    report
  end

  def self.dashboard_for(account, filters)
    campaigns = account.campaigns.community_reportable.includes(:community_campaign_report, :inbox).order(scheduled_at: :desc).to_a
    labels = account.labels.pluck(:id, :title).to_h
    options = campaigns.map { |campaign| campaign_option(campaign, labels) }
    options_by_id = options.index_by { |option| option[:id] }
    if filters[:campaign_id] && options.none? { |option| option[:id] == filters[:campaign_id] }
      raise ActiveRecord::RecordNotFound
    end
    selected = campaigns.select do |campaign|
      option = options_by_id.fetch(campaign.display_id)
      date = (campaign.scheduled_at || campaign.created_at).in_time_zone(filters[:zone]).to_date
      (filters[:from]..filters[:to]).cover?(date) &&
        (!filters[:campaign_id] || campaign.display_id == filters[:campaign_id]) &&
        (filters[:label_ids].empty? || option[:labels].any? { |label| filters[:label_ids].include?(label['id']) })
    end
    records = CommunityCampaignDelivery.where(account_id: account.id, campaign_id: selected.map(&:id))
    by_campaign = records.metrics_by_campaign
    summary = empty_metrics
    by_campaign.each_value { |metrics| metrics.each { |key, count| summary[key] += count } }
    rows = records.filtered_by_status(filters[:status]).matching_contact(filters[:query])
    total_rows = rows.count
    untracked_count = selected.count { |item| !item.community_campaign_report&.snapshot_complete? }
    available_labels = options.flat_map { |item| item[:labels] }.uniq { |label| label['id'] }.sort_by { |label| label['title'] }
    {
      summary: summary.merge(campaigns: selected.size, untracked_campaigns: untracked_count),
      distribution: records.group(:status).count,
      errors: records.where(status: 'failed').group(:error_code, :error_message).count.map do |(code, message), count|
        { code: code, message: message, count: count }
      end.sort_by { |error| -error[:count] }.first(10),
      timeline: records.daily_activity(from: filters[:from], to: filters[:to], zone: filters[:zone]),
      campaigns: selected.map do |campaign|
        campaign_option(campaign, labels).merge(metrics: by_campaign[campaign.id] || empty_metrics,
                                               historical: campaign.community_campaign_report&.historical? || false)
      end,
      options: { campaigns: options, labels: available_labels },
      recipients: rows.includes(:contact, :campaign).order(id: :desc).offset((filters[:page] - 1) * 25).limit(25).map(&:statistics_payload),
      pagination: { page: filters[:page], per_page: 25, total: total_rows, pages: (total_rows / 25.0).ceil },
      last_event_at: records.maximum(:last_event_at), generated_at: Time.current
    }
  end

  def self.empty_metrics
    { total: 0, sent: 0, delivered: 0, read: 0, failed: 0, pending: 0, unconfirmed: 0, historical: 0 }
  end

  def self.campaign_option(campaign, labels)
    report = campaign.community_campaign_report
    saved_labels = report.audience_labels if report&.snapshot_complete?
    saved_labels ||= campaign.audience.filter_map do |item|
      next unless item['type'] == 'Label'

      label_id = item['id'].to_i
      { 'id' => label_id, 'title' => labels[label_id] || "Etiqueta eliminada (#{label_id})" }
    end
    { id: campaign.display_id, title: campaign.title, status: campaign.campaign_status, inbox_name: campaign.inbox.name,
      scheduled_at: campaign.scheduled_at, started_at: campaign.started_at, completed_at: campaign.completed_at,
      labels: saved_labels }
  end
end
