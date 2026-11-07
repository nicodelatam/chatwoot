/* global axios */
export default {
  preview: (accountId, payload, signal) =>
    axios.post(
      `/api/v1/accounts/${accountId}/community_campaign_audience`,
      payload,
      { signal }
    ),
};
