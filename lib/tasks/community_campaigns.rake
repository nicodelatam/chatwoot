namespace :community_campaigns do
  desc 'Import existing delivery data without loading or changing Enterprise functionality'
  task import_history: :environment do
    source = CommunityCampaigns::HistoricalDelivery
    next unless source.table_exists?

    imported_ids = CommunityCampaignReport.where(snapshot_complete: true).select(:campaign_id)
    source.where.not(campaign_id: imported_ids).distinct.pluck(:campaign_id).each do |campaign_id|
      campaign = Campaign.community_reportable.find_by(id: campaign_id)
      next unless campaign

      report = CommunityCampaignReport.create_or_find_by!(campaign_id: campaign.id) do |record|
        record.account = campaign.account
        record.inbox = campaign.inbox
        record.historical = true
      end
      report.with_lock do
        next if report.snapshot_complete?

        records = source.where(account_id: campaign.account_id, campaign_id: campaign.id, inbox_id: campaign.inbox_id)
        records.find_in_batches(batch_size: 500) do |batch|
          CommunityCampaignDelivery.insert_all(batch.map(&:community_attributes), unique_by: :idx_community_deliveries_contact)
        end
        labels = CommunityCampaignReport.campaign_option(campaign, campaign.account.labels.pluck(:id, :title).to_h)[:labels]
        report.update!(audience_labels: labels, audience_size: records.count, snapshot_complete: true,
                       tracking_started_at: campaign.started_at)
      end
    end
    puts "Community campaign reports: #{CommunityCampaignReport.count}; deliveries: #{CommunityCampaignDelivery.count}"
  end
end
