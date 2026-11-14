export function campaignStatisticsLabels(t) {
  return {
    statuses: {
      pending: t('COMMUNITY_CAMPAIGNS.STATUSES.pending'),
      sent: t('COMMUNITY_CAMPAIGNS.STATUSES.sent'),
      delivered: t('COMMUNITY_CAMPAIGNS.STATUSES.delivered'),
      read: t('COMMUNITY_CAMPAIGNS.STATUSES.read'),
      failed: t('COMMUNITY_CAMPAIGNS.STATUSES.failed'),
      unconfirmed: t('COMMUNITY_CAMPAIGNS.STATUSES.unconfirmed'),
      awaiting: t('COMMUNITY_CAMPAIGNS.STATUSES.awaiting'),
      accepted: t('COMMUNITY_CAMPAIGNS.STATUSES.accepted'),
      delivered_all: t('COMMUNITY_CAMPAIGNS.STATUSES.delivered_all'),
      replied: t('COMMUNITY_CAMPAIGNS.STATUSES.replied'),
    },
    campaignStatuses: {
      active: t('COMMUNITY_CAMPAIGNS.CAMPAIGN_STATUSES.active'),
      processing: t('COMMUNITY_CAMPAIGNS.CAMPAIGN_STATUSES.processing'),
      completed: t('COMMUNITY_CAMPAIGNS.CAMPAIGN_STATUSES.completed'),
    },
    metrics: [
      {
        key: 'total',
        status: 'all',
        label: t('COMMUNITY_CAMPAIGNS.TOTAL'),
        hint: t('COMMUNITY_CAMPAIGNS.TOTAL_HINT'),
      },
      {
        key: 'sent',
        status: 'accepted',
        label: t('COMMUNITY_CAMPAIGNS.SENT'),
        hint: t('COMMUNITY_CAMPAIGNS.SENT_HINT'),
      },
      {
        key: 'delivered',
        status: 'delivered_all',
        label: t('COMMUNITY_CAMPAIGNS.DELIVERED'),
        hint: t('COMMUNITY_CAMPAIGNS.DELIVERED_HINT'),
      },
      {
        key: 'read',
        status: 'read',
        label: t('COMMUNITY_CAMPAIGNS.READ'),
        hint: t('COMMUNITY_CAMPAIGNS.READ_HINT'),
      },
      {
        key: 'failed',
        status: 'failed',
        label: t('COMMUNITY_CAMPAIGNS.FAILED'),
        hint: t('COMMUNITY_CAMPAIGNS.FAILED_HINT'),
      },
      {
        key: 'pending',
        status: 'awaiting',
        label: t('COMMUNITY_CAMPAIGNS.PENDING'),
        hint: t('COMMUNITY_CAMPAIGNS.PENDING_HINT'),
      },
    ],
  };
}
