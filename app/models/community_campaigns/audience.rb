class CommunityCampaigns::Audience
  attr_reader :campaign

  def initialize(campaign)
    @campaign = campaign
  end

  def config
    campaign.trigger_rules&.fetch('community_audience', nil) || { 'mode' => 'labels' }
  end

  def validate!
    unless config.is_a?(Hash) && %w[labels failed].include?(config['mode'])
      raise CustomExceptions::CommunityCampaignFilterError, 'El tipo de audiencia no es válido.'
    end
    label_ids = campaign.audience.map { |item| item['id'] if item['type'] == 'Label' }.compact
    unless label_ids.size <= 50 && label_ids.all? { |id| id.is_a?(Integer) && id.positive? } &&
           campaign.account.labels.where(id: label_ids).count == label_ids.uniq.size
      raise CustomExceptions::CommunityCampaignFilterError, 'Revisa las etiquetas seleccionadas.'
    end
    return unless config['mode'] == 'failed'

    cloud_channel = campaign.inbox&.channel.is_a?(Channel::Whatsapp) && campaign.inbox.channel.provider == 'whatsapp_cloud'
    unless cloud_channel && !ChatwootApp.enterprise?
      raise CustomExceptions::CommunityCampaignFilterError, 'Esta audiencia requiere WhatsApp Cloud en Community.'
    end
    id = config['source_campaign_id']
    codes = config['error_codes'] || []
    unless id.is_a?(Integer) && id.positive? && codes.is_a?(Array) && codes.size <= 20 &&
           codes.all? { |code| code.is_a?(String) && code.match?(/\A[a-zA-Z0-9_-]{1,50}\z/) }
      raise CustomExceptions::CommunityCampaignFilterError, 'Revisa la campaña de origen y los códigos de error.'
    end
    unless source_campaign
      raise CustomExceptions::CommunityCampaignFilterError, 'Elige una campaña finalizada de este canal y esta cuenta.'
    end
  end

  def source_campaign
    @source_campaign ||= campaign.account.campaigns.community_reportable.completed.where(inbox_id: campaign.inbox_id)
                                 .where.not(id: campaign.id).find_by(display_id: config['source_campaign_id'])
  end

  def labels
    ids = campaign.audience.filter_map { |item| item['id'] if item['type'] == 'Label' }
    campaign.account.labels.where(id: ids).pluck(:id, :title).map { |id, title| { 'id' => id, 'title' => title } }
  end

  def contacts
    validate!
    scope = campaign.account.contacts.where(blocked: false)
    if config['mode'] == 'failed'
      failures = source_campaign.community_campaign_deliveries.where(status: 'failed', delivered_at: nil, read_at: nil)
      failures = failures.where(error_code: config['error_codes']) if config['error_codes'].present?
      # A successful or still-running retry must not be included in another retry.
      attempts = CommunityCampaignDelivery.where(account_id: campaign.account_id, campaign_id: retry_family_ids)
                                         .where.not(campaign_id: campaign.id)
      occupied = attempts.where.not(status: 'failed').or(attempts.where.not(delivered_at: nil)).or(attempts.where.not(read_at: nil))
      scope = scope.where(id: failures.select(:contact_id)).where.not(id: occupied.where.not(contact_id: nil).select(:contact_id))
      return scope if labels.empty?
    end
    return scope.none if labels.empty?

    scope.tagged_with(labels.pluck('title'), any: true).distinct
  end

  def retry_family_ids
    rows = campaign.account.campaigns.community_reportable.pluck(:id, :display_id, :trigger_rules)
    display_ids = [source_campaign.display_id]
    loop do
      children = rows.filter_map { |_, id, rules| id if display_ids.include?(rules&.dig('community_audience', 'source_campaign_id')) }
      expanded = (display_ids + children).uniq
      break if expanded == display_ids

      display_ids = expanded
    end
    rows.filter_map { |id, display_id, _| id if display_ids.include?(display_id) }
  end

  def preview(zone:, scheduled_at:)
    selected = contacts
    today = zone.today
    window = day_window(today, zone)
    activity = campaign.account.campaigns.community_reportable.where.not(id: campaign.id)
    sent = activity.where(started_at: window).order(started_at: :desc)
    attempts = CommunityCampaignDelivery.where(account_id: campaign.account_id).where.not(campaign_id: campaign.id)
    attempts = attempts.where(attempted_at: window).or(attempts.where(sent_at: window))
    day = scheduled_at.in_time_zone(zone).to_date
    scheduled_window = day_window(day, zone)
    planned = activity.active.where(scheduled_at: scheduled_window).order(:scheduled_at)
    sources = campaign.account.campaigns.community_reportable.completed.where(inbox_id: campaign.inbox_id)
    sources = sources.where(id: CommunityCampaignDelivery.where(account_id: campaign.account_id, status: 'failed').select(:campaign_id))
    errors = source_campaign&.community_campaign_deliveries&.where(status: 'failed') if config['mode'] == 'failed'
    {
      total: selected.count, timezone: zone.tzinfo.name, today: today.iso8601, scheduled_day: day.iso8601,
      campaigns: sources.order(created_at: :desc).map { |item| { id: item.display_id, title: item.title } },
      errors: errors ? errors.group(:error_code).count.map { |code, count| { code: code, count: count } } : [],
      sent_today: sent.map { |item| { id: item.display_id, title: item.title, started_at: item.started_at } },
      scheduled: planned.map { |item| { id: item.display_id, title: item.title, scheduled_at: item.scheduled_at } },
      overlap_today: selected.where(id: attempts.where.not(contact_id: nil).select(:contact_id)).count
    }
  end

  private

  def day_window(day, zone)
    zone.local(day.year, day.month, day.day)...zone.local(day.next_day.year, day.next_day.month, day.next_day.day)
  end
end
