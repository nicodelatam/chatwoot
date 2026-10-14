/* global axios */

const resource = accountId =>
  `/api/v1/accounts/${accountId}/community_whatsapp_calls`;

export default {
  index: (accountId, sessionId) =>
    axios.get(resource(accountId), { params: { session_id: sessionId } }),
  show: (accountId, id, sessionId) =>
    axios.get(`${resource(accountId)}/${id}`, {
      params: { session_id: sessionId },
    }),
  permission: (accountId, conversationId) =>
    axios.get(`${resource(accountId)}/permission`, {
      params: { conversation_id: conversationId },
    }),
  configure: (accountId, payload) =>
    axios.post(`${resource(accountId)}/configure`, payload),
  requestPermission: (accountId, payload) =>
    axios.post(`${resource(accountId)}/request_permission`, payload),
  create: (accountId, payload) => axios.post(resource(accountId), payload),
  preAccept: (accountId, id, payload) =>
    axios.post(`${resource(accountId)}/${id}/pre_accept`, payload),
  accept: (accountId, id, payload) =>
    axios.post(`${resource(accountId)}/${id}/accept`, payload),
  reject: (accountId, id, payload) =>
    axios.post(`${resource(accountId)}/${id}/reject`, payload),
  terminate: (accountId, id, payload) =>
    axios.post(`${resource(accountId)}/${id}/terminate`, payload),
};
