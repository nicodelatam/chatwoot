/* global axios */
export default {
  get: (accountId, params, signal) =>
    axios.get(`/api/v1/accounts/${accountId}/community_campaign_statistics`, {
      params,
      signal,
    }),
};
