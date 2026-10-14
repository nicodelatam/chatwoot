import { computed, ref } from 'vue';
import CommunityWhatsappCallsAPI from 'dashboard/api/communityWhatsappCalls';

const CALL_TERMINAL_STATES = ['completed', 'rejected', 'missed', 'failed'];
const SDP_GATHERING_TIMEOUT_MS = 10000;
const CONNECTION_TIMEOUT_MS = 15000;
const DISCONNECTION_GRACE_MS = 5000;
const OUTGOING_RING_TIMEOUT_MS = 60000;

const calls = ref([]);
const inboxes = ref([]);
const activeCall = ref(null);
const panelOpen = ref(false);
const error = ref('');
const permissionConversationId = ref(null);
const canRequestPermission = ref(false);
const busy = ref(false);
const muted = ref(false);
let accountId = null;
let sessionId = null;
let listTimer = null;
let callTimer = null;
let pc = null;
let localStream = null;
let remoteAudio = null;
let mediaAuthorized = false;
let connectionTimer = null;
let disconnectionTimer = null;
let outgoingRingTimer = null;
let monitoredPeer = null;
const terminationRequests = new Map();
let operationLock = false;
let lockGeneration = null;
let accountGeneration = 0;
let pollGeneration = null;

const isActive = computed(
  () =>
    activeCall.value && !CALL_TERMINAL_STATES.includes(activeCall.value.status)
);
const incomingCall = computed(() => {
  if (isActive.value) return null;
  return calls.value.find(
    call => call.direction === 'incoming' && call.status === 'ringing'
  );
});
const configuredInboxIds = computed(
  () =>
    new Set(inboxes.value.filter(inbox => inbox.enabled).map(inbox => inbox.id))
);

const getSessionId = () => {
  if (!sessionId) sessionId = window.crypto.randomUUID();
  return sessionId;
};

const responseData = response => response?.data || {};
const errorMessage = err => {
  if (err?.response?.data?.code === 'permission_required') {
    return 'COMMUNITY_CALLING.ERRORS.PERMISSION_REQUIRED';
  }
  if (err?.name === 'NotAllowedError') {
    return 'COMMUNITY_CALLING.ERRORS.MICROPHONE_DENIED';
  }
  if (err?.name === 'NotFoundError') {
    return 'COMMUNITY_CALLING.ERRORS.MICROPHONE_MISSING';
  }
  return (
    err?.response?.data?.error ||
    (err?.message?.startsWith('COMMUNITY_CALLING.ERRORS.') && err.message) ||
    'COMMUNITY_CALLING.ERRORS.GENERIC'
  );
};

const ensureCurrentAccount = generation => {
  if (generation !== accountGeneration) {
    throw new Error('COMMUNITY_CALLING.ERRORS.ACCOUNT_CHANGED');
  }
};

const beginPoll = generation => {
  if (pollGeneration === generation) return false;
  pollGeneration = generation;
  return true;
};

const endPoll = generation => {
  if (pollGeneration === generation) pollGeneration = null;
};

const terminateCallForSession = (targetAccountId, callId) => {
  const key = `${targetAccountId}:${callId}:${getSessionId()}`;
  if (terminationRequests.has(key)) return terminationRequests.get(key);
  const request = CommunityWhatsappCallsAPI.terminate(targetAccountId, callId, {
    session_id: getSessionId(),
  })
    .catch(() => {})
    .finally(() => terminationRequests.delete(key));
  terminationRequests.set(key, request);
  return request;
};

const stopMedia = () => {
  if (connectionTimer) window.clearTimeout(connectionTimer);
  if (disconnectionTimer) window.clearTimeout(disconnectionTimer);
  if (outgoingRingTimer) window.clearTimeout(outgoingRingTimer);
  connectionTimer = null;
  disconnectionTimer = null;
  outgoingRingTimer = null;
  monitoredPeer = null;
  mediaAuthorized = false;
  if (pc) {
    pc.ontrack = null;
    pc.onconnectionstatechange = null;
    pc.close();
    pc = null;
  }
  localStream?.getTracks().forEach(track => track.stop());
  localStream = null;
  if (remoteAudio) {
    remoteAudio.pause();
    remoteAudio.srcObject = null;
    remoteAudio = null;
  }
  muted.value = false;
};

const clearCall = () => {
  activeCall.value = null;
  if (callTimer) window.clearInterval(callTimer);
  callTimer = null;
  stopMedia();
};

const failActiveCall = (peer, generation, err) => {
  const failedCall = activeCall.value;
  if (generation !== accountGeneration || !failedCall || !peer || pc !== peer) {
    return;
  }
  error.value = errorMessage(err);
  panelOpen.value = true;
  const failedAccountId = accountId;
  calls.value = calls.value.filter(call => call.id !== failedCall.id);
  clearCall();
  terminateCallForSession(failedAccountId, failedCall.id);
};

const startConnectionTimeout = (peer, generation) => {
  if (
    connectionTimer ||
    peer !== pc ||
    peer.connectionState === 'connected' ||
    peer.connectionState === 'failed' ||
    peer.connectionState === 'closed'
  ) {
    return;
  }
  connectionTimer = window.setTimeout(() => {
    failActiveCall(
      peer,
      generation,
      new Error('COMMUNITY_CALLING.ERRORS.CONNECTION_TIMEOUT')
    );
  }, CONNECTION_TIMEOUT_MS);
};

const startOutgoingRingTimeout = (peer, generation) => {
  if (outgoingRingTimer) window.clearTimeout(outgoingRingTimer);
  outgoingRingTimer = window.setTimeout(() => {
    if (
      activeCall.value?.direction === 'outgoing' &&
      activeCall.value.status === 'ringing'
    ) {
      failActiveCall(
        peer,
        generation,
        new Error('COMMUNITY_CALLING.ERRORS.RING_TIMEOUT')
      );
    }
  }, OUTGOING_RING_TIMEOUT_MS);
};

const monitorPeerConnection = (peer, generation) => {
  if (monitoredPeer === peer) return;
  monitoredPeer = peer;
  peer.onconnectionstatechange = () => {
    if (peer !== pc || generation !== accountGeneration) return;
    if (peer.connectionState === 'connected') {
      if (connectionTimer) window.clearTimeout(connectionTimer);
      if (disconnectionTimer) window.clearTimeout(disconnectionTimer);
      connectionTimer = null;
      disconnectionTimer = null;
      if (
        activeCall.value?.status === 'active' &&
        mediaAuthorized &&
        !muted.value
      ) {
        localStream?.getAudioTracks().forEach(track => {
          track.enabled = true;
        });
      }
    } else if (
      peer.connectionState === 'failed' ||
      peer.connectionState === 'closed'
    ) {
      failActiveCall(
        peer,
        generation,
        new Error('COMMUNITY_CALLING.ERRORS.CONNECTION_FAILED')
      );
    } else if (peer.connectionState === 'disconnected' && !disconnectionTimer) {
      disconnectionTimer = window.setTimeout(() => {
        if (peer.connectionState !== 'connected') {
          failActiveCall(
            peer,
            generation,
            new Error('COMMUNITY_CALLING.ERRORS.CONNECTION_FAILED')
          );
        }
      }, DISCONNECTION_GRACE_MS);
    }
  };
  peer.onconnectionstatechange();
};

const resetForAccount = nextAccountId => {
  if (accountId === nextAccountId) return;
  if (activeCall.value?.id && accountId) {
    terminateCallForSession(accountId, activeCall.value.id);
  }
  accountGeneration += 1;
  if (listTimer) window.clearInterval(listTimer);
  if (callTimer) window.clearInterval(callTimer);
  listTimer = null;
  callTimer = null;
  stopMedia();
  accountId = nextAccountId;
  calls.value = [];
  inboxes.value = [];
  activeCall.value = null;
  panelOpen.value = false;
  error.value = '';
  permissionConversationId.value = null;
  canRequestPermission.value = false;
  operationLock = false;
  lockGeneration = null;
  pollGeneration = null;
  connectionTimer = null;
  disconnectionTimer = null;
  outgoingRingTimer = null;
  monitoredPeer = null;
  busy.value = false;
};

const syncCalls = async () => {
  if (!accountId) return;
  const requestedAccountId = accountId;
  const requestedGeneration = accountGeneration;
  if (!beginPoll(requestedGeneration)) return;
  try {
    const { calls: nextCalls = [], inboxes: nextInboxes = [] } = responseData(
      await CommunityWhatsappCallsAPI.index(requestedAccountId, getSessionId())
    );
    if (requestedGeneration !== accountGeneration) return;
    calls.value = nextCalls;
    inboxes.value = nextInboxes;
    if (activeCall.value) {
      const updatedCall = nextCalls.find(
        call => call.id === activeCall.value.id
      );
      if (updatedCall)
        activeCall.value = { ...activeCall.value, ...updatedCall };
    }
    if (
      activeCall.value &&
      CALL_TERMINAL_STATES.includes(activeCall.value.status)
    ) {
      clearCall();
    }
  } catch (err) {
    // Keep an active call and its media alive during a transient list failure.
    if (requestedGeneration === accountGeneration && !activeCall.value) {
      error.value = errorMessage(err);
    }
  } finally {
    endPoll(requestedGeneration);
  }
};

const syncActiveCall = async () => {
  if (!accountId || !activeCall.value) return;
  const requestedAccountId = accountId;
  const requestedCallId = activeCall.value.id;
  const requestedGeneration = accountGeneration;
  if (!beginPoll(requestedGeneration)) return;
  let applyingRemoteDescription = false;
  let peerAtStart = null;
  try {
    const details = responseData(
      await CommunityWhatsappCallsAPI.show(
        requestedAccountId,
        requestedCallId,
        getSessionId()
      )
    );
    if (
      requestedGeneration !== accountGeneration ||
      activeCall.value?.id !== requestedCallId
    ) {
      return;
    }
    activeCall.value = { ...activeCall.value, ...details };
    if (CALL_TERMINAL_STATES.includes(activeCall.value.status)) {
      clearCall();
      return;
    }
    if (
      activeCall.value.direction === 'outgoing' &&
      details.sdp_answer &&
      pc &&
      !pc.currentRemoteDescription
    ) {
      if (outgoingRingTimer) window.clearTimeout(outgoingRingTimer);
      outgoingRingTimer = null;
      peerAtStart = pc;
      applyingRemoteDescription = true;
      await peerAtStart.setRemoteDescription({
        type: 'answer',
        sdp: details.sdp_answer,
      });
      ensureCurrentAccount(requestedGeneration);
      applyingRemoteDescription = false;
      monitorPeerConnection(peerAtStart, requestedGeneration);
      startConnectionTimeout(peerAtStart, requestedGeneration);
    } else if (
      activeCall.value.direction === 'outgoing' &&
      ['connecting', 'active'].includes(activeCall.value.status) &&
      pc
    ) {
      if (outgoingRingTimer) window.clearTimeout(outgoingRingTimer);
      outgoingRingTimer = null;
      peerAtStart = pc;
      monitorPeerConnection(peerAtStart, requestedGeneration);
      startConnectionTimeout(peerAtStart, requestedGeneration);
    }
    if (
      activeCall.value.direction === 'outgoing' &&
      activeCall.value.status === 'active'
    ) {
      mediaAuthorized = true;
    }
    if (
      activeCall.value.status === 'active' &&
      pc?.connectionState === 'connected' &&
      mediaAuthorized &&
      !muted.value
    ) {
      localStream?.getAudioTracks().forEach(track => {
        track.enabled = true;
      });
    }
  } catch (err) {
    if (applyingRemoteDescription) {
      failActiveCall(peerAtStart, requestedGeneration, err);
    }
    // Transient API failures continue on the next one-second poll.
  } finally {
    endPoll(requestedGeneration);
  }
};

const start = nextAccountId => {
  resetForAccount(nextAccountId);
  if (!accountId || listTimer) return;
  syncCalls();
  listTimer = window.setInterval(syncCalls, 3000);
};

const stop = () => {
  if (activeCall.value?.id && accountId) {
    terminateCallForSession(accountId, activeCall.value.id);
  }
  accountGeneration += 1;
  if (listTimer) window.clearInterval(listTimer);
  if (callTimer) window.clearInterval(callTimer);
  listTimer = null;
  callTimer = null;
  stopMedia();
  activeCall.value = null;
  operationLock = false;
  lockGeneration = null;
  busy.value = false;
  pollGeneration = null;
};

const waitForIceGathering = peer =>
  new Promise((resolve, reject) => {
    if (peer.iceGatheringState === 'complete') {
      resolve();
      return;
    }
    let timeout;
    const onGathering = () => {
      if (peer.iceGatheringState !== 'complete') return;
      window.clearTimeout(timeout);
      peer.removeEventListener('icegatheringstatechange', onGathering);
      resolve();
    };
    timeout = window.setTimeout(() => {
      peer.removeEventListener('icegatheringstatechange', onGathering);
      reject(new Error('COMMUNITY_CALLING.ERRORS.SDP_GATHERING'));
    }, SDP_GATHERING_TIMEOUT_MS);
    peer.addEventListener('icegatheringstatechange', onGathering);
  });

const waitForConnection = peer =>
  new Promise((resolve, reject) => {
    if (peer.connectionState === 'connected') {
      resolve();
      return;
    }
    if (
      peer.connectionState === 'failed' ||
      peer.connectionState === 'closed'
    ) {
      reject(new Error('COMMUNITY_CALLING.ERRORS.CONNECTION_FAILED'));
      return;
    }
    let timeout;
    const onStateChange = () => {
      if (peer.connectionState === 'connected') {
        window.clearTimeout(timeout);
        peer.removeEventListener('connectionstatechange', onStateChange);
        resolve();
      } else if (
        peer.connectionState === 'failed' ||
        peer.connectionState === 'closed'
      ) {
        window.clearTimeout(timeout);
        peer.removeEventListener('connectionstatechange', onStateChange);
        reject(new Error('COMMUNITY_CALLING.ERRORS.CONNECTION_FAILED'));
      }
    };
    timeout = window.setTimeout(() => {
      peer.removeEventListener('connectionstatechange', onStateChange);
      reject(new Error('COMMUNITY_CALLING.ERRORS.CONNECTION_TIMEOUT'));
    }, CONNECTION_TIMEOUT_MS);
    peer.addEventListener('connectionstatechange', onStateChange);
  });

const preparePeer = async generation => {
  if (!navigator.mediaDevices?.getUserMedia || !window.RTCPeerConnection) {
    throw new Error('COMMUNITY_CALLING.ERRORS.BROWSER_UNSUPPORTED');
  }
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  if (generation !== accountGeneration) {
    stream.getTracks().forEach(track => track.stop());
    ensureCurrentAccount(generation);
  }
  localStream = stream;
  localStream.getAudioTracks().forEach(track => {
    track.enabled = false;
  });
  pc = new RTCPeerConnection();
  localStream.getTracks().forEach(track => pc.addTrack(track, localStream));
  pc.ontrack = event => {
    if (!remoteAudio) remoteAudio = new Audio();
    remoteAudio.autoplay = true;
    remoteAudio.srcObject = event.streams[0];
    remoteAudio.play().catch(() => {});
  };
  return pc;
};

const withLock = async operation => {
  if (operationLock && lockGeneration === accountGeneration) return null;
  operationLock = true;
  busy.value = true;
  error.value = '';
  const context = { accountId, generation: accountGeneration };
  lockGeneration = context.generation;
  try {
    return await operation(context);
  } catch (err) {
    if (context.generation === accountGeneration) {
      error.value = errorMessage(err);
      stopMedia();
      if (
        activeCall.value?.direction === 'outgoing' &&
        activeCall.value.status === 'ringing'
      ) {
        activeCall.value = null;
      }
      if (activeCall.value?.status === 'connecting') activeCall.value = null;
    }
    return null;
  } finally {
    if (lockGeneration === context.generation) {
      operationLock = false;
      busy.value = false;
    }
  }
};

const startCallPolling = () => {
  if (callTimer) window.clearInterval(callTimer);
  callTimer = window.setInterval(syncActiveCall, 1000);
};

const startOutgoingCall = conversationId =>
  withLock(async ({ accountId: requestAccountId, generation }) => {
    permissionConversationId.value = null;
    canRequestPermission.value = false;
    const permission = responseData(
      await CommunityWhatsappCallsAPI.permission(
        requestAccountId,
        conversationId
      )
    );
    ensureCurrentAccount(generation);
    if (!permission.can_call) {
      if (permission.can_request) {
        permissionConversationId.value = conversationId;
      }
      canRequestPermission.value = Boolean(permission.can_request);
      if (permission.status === 'permanent') {
        error.value = 'COMMUNITY_CALLING.ERRORS.PERMISSION_PERMANENT';
      } else if (permission.status === 'temporary') {
        error.value = 'COMMUNITY_CALLING.ERRORS.PERMISSION_TEMPORARY';
      } else {
        error.value = 'COMMUNITY_CALLING.ERRORS.PERMISSION_REQUIRED';
      }
      return null;
    }
    const peer = await preparePeer(generation);
    const offer = await peer.createOffer();
    ensureCurrentAccount(generation);
    await peer.setLocalDescription(offer);
    ensureCurrentAccount(generation);
    await waitForIceGathering(peer);
    ensureCurrentAccount(generation);
    try {
      const result = responseData(
        await CommunityWhatsappCallsAPI.create(requestAccountId, {
          conversation_id: conversationId,
          sdp_offer: peer.localDescription.sdp,
          session_id: getSessionId(),
        })
      );
      if (generation !== accountGeneration) {
        await terminateCallForSession(requestAccountId, result.id);
        return null;
      }
      activeCall.value = result;
      mediaAuthorized = false;
      monitorPeerConnection(peer, generation);
      if (!activeCall.value) return null;
      if (result.status === 'ringing') {
        startOutgoingRingTimeout(peer, generation);
      }
      startCallPolling();
      await syncActiveCall();
      ensureCurrentAccount(generation);
      return result;
    } catch (err) {
      ensureCurrentAccount(generation);
      if (err?.response?.data?.code === 'permission_required') {
        permissionConversationId.value = conversationId;
        canRequestPermission.value = true;
      }
      throw err;
    }
  });

const requestPermission = conversationId =>
  withLock(async ({ accountId: requestAccountId, generation }) => {
    await CommunityWhatsappCallsAPI.requestPermission(requestAccountId, {
      conversation_id: conversationId,
    });
    if (generation !== accountGeneration) return null;
    permissionConversationId.value = null;
    canRequestPermission.value = false;
    error.value = 'COMMUNITY_CALLING.ERRORS.PERMISSION_REQUESTED';
    return null;
  });

const acceptIncomingCall = call =>
  withLock(async ({ accountId: requestAccountId, generation }) => {
    let preAcceptAttempted = false;
    try {
      const details = responseData(
        await CommunityWhatsappCallsAPI.show(
          requestAccountId,
          call.id,
          getSessionId()
        )
      );
      ensureCurrentAccount(generation);
      const peer = await preparePeer(generation);
      await peer.setRemoteDescription({
        type: 'offer',
        sdp: details.sdp_offer,
      });
      ensureCurrentAccount(generation);
      const answer = await peer.createAnswer();
      ensureCurrentAccount(generation);
      await peer.setLocalDescription(answer);
      ensureCurrentAccount(generation);
      await waitForIceGathering(peer);
      ensureCurrentAccount(generation);
      preAcceptAttempted = true;
      await CommunityWhatsappCallsAPI.preAccept(requestAccountId, call.id, {
        sdp_answer: peer.localDescription.sdp,
        session_id: getSessionId(),
      });
      ensureCurrentAccount(generation);
      activeCall.value = { ...call, ...details, status: 'connecting' };
      startCallPolling();
      monitorPeerConnection(peer, generation);
      startConnectionTimeout(peer, generation);
      await waitForConnection(peer);
      ensureCurrentAccount(generation);
      const accepted = responseData(
        await CommunityWhatsappCallsAPI.accept(requestAccountId, call.id, {
          session_id: getSessionId(),
        })
      );
      if (generation !== accountGeneration) {
        await terminateCallForSession(requestAccountId, call.id);
        return null;
      }
      mediaAuthorized = true;
      localStream?.getAudioTracks().forEach(track => {
        track.enabled = true;
      });
      activeCall.value = { ...call, ...details, ...accepted };
      startCallPolling();
      return null;
    } catch (err) {
      if (preAcceptAttempted) {
        await terminateCallForSession(requestAccountId, call.id);
        calls.value = calls.value.filter(item => item.id !== call.id);
      }
      if (generation === accountGeneration) {
        activeCall.value = null;
        stopMedia();
      }
      throw err;
    }
  });

const rejectIncomingCall = call =>
  withLock(async ({ accountId: requestAccountId, generation }) => {
    await CommunityWhatsappCallsAPI.reject(requestAccountId, call.id, {
      session_id: getSessionId(),
    });
    ensureCurrentAccount(generation);
    calls.value = calls.value.filter(item => item.id !== call.id);
    return null;
  });

const terminateCall = () =>
  withLock(async ({ accountId: requestAccountId, generation }) => {
    if (!activeCall.value) return null;
    const callId = activeCall.value.id;
    try {
      await CommunityWhatsappCallsAPI.terminate(requestAccountId, callId, {
        session_id: getSessionId(),
      });
    } catch (err) {
      if (generation === accountGeneration) {
        if (callTimer) window.clearInterval(callTimer);
        callTimer = null;
        stopMedia();
      }
      throw err;
    }
    ensureCurrentAccount(generation);
    if (activeCall.value?.id !== callId) return null;
    clearCall();
    return null;
  });

const toggleMute = () => {
  muted.value = !muted.value;
  localStream?.getAudioTracks().forEach(track => {
    track.enabled = mediaAuthorized && !muted.value;
  });
};

const configureInbox = (inboxId, enabled) =>
  withLock(async ({ accountId: requestAccountId, generation }) => {
    await CommunityWhatsappCallsAPI.configure(requestAccountId, {
      inbox_id: inboxId,
      enabled,
    });
    if (generation !== accountGeneration) return null;
    await syncCalls();
    return null;
  });

export function useCommunityWhatsappCalling() {
  return {
    calls,
    inboxes,
    activeCall,
    incomingCall,
    panelOpen,
    error,
    permissionConversationId,
    canRequestPermission,
    busy,
    muted,
    isActive,
    configuredInboxIds,
    start,
    stop,
    syncCalls,
    startOutgoingCall,
    requestPermission,
    acceptIncomingCall,
    rejectIncomingCall,
    terminateCall,
    toggleMute,
    configureInbox,
  };
}
