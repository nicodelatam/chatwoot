# Community WhatsApp calling

This fork provides an independent voice integration for agents to receive and place WhatsApp calls in their browser. It uses Meta Cloud API for signaling and browser WebRTC for audio. It does not record calls.

## License boundary

Reviewed on 2026-10-14 against this fork's `LICENSE` and `enterprise/LICENSE`.

- The [root license](https://github.com/nicodelatam/chatwoot/blob/develop/LICENSE) permits using, modifying, distributing and selling the code outside `enterprise/` under MIT, while retaining the copyright and permission notices. Third-party components keep their own licenses.
- The [Enterprise license](https://github.com/nicodelatam/chatwoot/blob/develop/enterprise/LICENSE) permits development/testing without a subscription, but requires an appropriate subscription and licensed seats for production use of that code and modifications to it.
- These new controllers, models, jobs, services and components were written independently from Meta's public API documentation. They do not load Enterprise call services, remove subscription checks, enable paid feature flags or relocate Enterprise code.
- The image workflow removes `enterprise/` before building and verifies its absence in the resulting image. It sets `CW_EDITION=ce` and `DISABLE_ENTERPRISE=true`. Preserve the MIT notice in this fork and its images. This review concerns the published source licenses; it is not a review of any separate commercial agreement.

The source fork is [`nicodelatam/chatwoot`](https://github.com/nicodelatam/chatwoot), default branch `develop`. The vendor upstream remains [`chatwoot/chatwoot`](https://github.com/chatwoot/chatwoot). [`nicodelatam/chatwoot-nico`](https://github.com/nicodelatam/chatwoot-nico) owns the deployment configuration.

## Meta prerequisites

The [Calling overview](https://developers.facebook.com/documentation/business-messaging/whatsapp/calling/) states:

1. Use a business phone number registered with Cloud API, not a WhatsApp Business app coexistence number.
2. The business needs a daily messaging limit of at least 2,000 unique recipients. Public test numbers have different eligibility rules.
3. The Meta app must have `whatsapp_business_messaging`, be subscribed to the WABA, and subscribe to the `calls` webhook field in App Dashboard → WhatsApp → Configuration. The WABA callback registration does not replace the app-level webhook subscription.
4. Configure a valid Meta app secret so webhook signatures can be verified. The existing `WHATSAPP_APP_SECRET` installation config or channel app-secret fields are used.
5. Enable calling on the phone number. This integration refuses numbers configured for SIP. Inspecting settings requires the documented `whatsapp_business_management` access.
6. Use HTTPS and a browser with microphone access. The browser must reach Meta's WebRTC media servers; validate the real agent network before rollout.

Meta allows incoming calls wherever Cloud API is available. Its current outbound exclusions apply to the **business** number country code: United States, Canada, Egypt, Vietnam and Nigeria. Meta remains authoritative for eligibility, billing and call limits.

## Use

1. Create or connect a WhatsApp Cloud API inbox using the existing inbox setup. Subscribe the app to `calls` and verify the secret configuration.
2. Open **WhatsApp calls** in the dashboard. An administrator can enable the desired inbox.
3. A customer calls the business number from WhatsApp. An inbox member sees the caller panel and can answer or decline. The first successful acceptance reserves the call for that browser session.
4. To place a call, open the contact's conversation and select **Call on WhatsApp**. The server checks current permission with Meta before asking for the microphone.
5. If permission is missing, select **Request call permission**. The contact must approve before retrying. Free-form requests are limited to the 24-hour customer service window. Outside that window, use an approved call-permission template through the existing template sender, or have the contact enable calls in the business profile.
6. Use mute or **End call**. Closing the dashboard or switching accounts attempts to terminate the call. A server watchdog retries remote cleanup if a browser stops sending heartbeats.

The backend reads Meta's `start_call` and `send_call_permission_request` actions for each request, including expiration, revocation and quota restrictions. It does not infer consent from old webhooks or cache it indefinitely.

## Integration contract

Authenticated endpoints live at `/api/v1/accounts/:account_id/community_whatsapp_calls`. They require account and inbox access; configuration also requires an administrator. They use an independent table and do not share Enterprise endpoints.

| Endpoint | Purpose |
| --- | --- |
| `GET /` | Accessible inboxes and ongoing calls for this browser session |
| `GET /:id` | Authorized call details, SDP and owner heartbeat |
| `GET /permission?conversation_id=...` | Current permission and allowed actions from Meta |
| `POST /configure` | Enable or disable a Cloud API inbox |
| `POST /request_permission` | Send a permitted request inside the service window |
| `POST /` | Reserve the agent/conversation and initiate an outgoing call |
| `POST /:id/pre_accept` | Claim an incoming call and exchange its answer SDP |
| `POST /:id/accept` | Accept after WebRTC connects, using the same SDP |
| `POST /:id/reject` | Decline a ringing incoming call |
| `POST /:id/terminate` | End a call owned by this browser session |

Microphone tracks stay disabled until acceptance. SDP is filtered from request logs and removed when a call finishes. Ended calls add an activity entry to the conversation. Duplicate and out-of-order webhooks cannot reopen a finished call. Database indexes prevent two ongoing calls for the same agent or conversation. Incoming webhook jobs use the normal per-contact WhatsApp mutex and the default Sidekiq queue.

## Build and rollout

The **Community WhatsApp calling** workflow validates the frontend, builds Community Edition, checks Ruby syntax, migrates an isolated PostgreSQL database, checks Rails routes, and publishes `ghcr.io/nicodelatam/chatwoot-community:<commit-sha>` only after validation succeeds. Dispatch the workflow on the reviewed commit for later releases.

Pin both Rails and Sidekiq in `chatwoot-nico` to the same verified image SHA. Keep the existing database, Redis, storage, secrets and domains. The normal `db:chatwoot_prepare` startup applies the additive call-table migration. Confirm backup freshness before production deployment. Retain the previous image reference for rollback; leave the additive table in place when reverting code.

Before enabling a production inbox, verify a real inbound call, consent and outbound call, two-agent acceptance, microphone refusal, mute, remote hangup, browser closure, and the agent network's media connectivity. A successful build or mocked signaling check does not prove real Meta audio works.

## Official sources

- [Inbound calls and pre-accept](https://developers.facebook.com/documentation/business-messaging/whatsapp/calling/user-initiated-calls/)
- [Outbound connect and status webhooks](https://developers.facebook.com/documentation/business-messaging/whatsapp/calling/business-initiated-calls/)
- [Permission state, permanent permissions and limits](https://developers.facebook.com/documentation/business-messaging/whatsapp/calling/user-call-permissions/)
- [Phone settings](https://developers.facebook.com/documentation/business-messaging/whatsapp/calling/call-settings/)
- [SDP reference](https://developers.facebook.com/documentation/business-messaging/whatsapp/calling/reference/)
- [Calling errors](https://developers.facebook.com/documentation/business-messaging/whatsapp/calling/troubleshooting/)

Meta's documentation was read directly on 2026-10-14, including the `.md` representations when the regular documentation fetch was rate-limited.
