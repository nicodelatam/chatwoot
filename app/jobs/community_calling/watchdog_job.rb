# Expire ringing calls and terminate calls whose browser stopped sending heartbeats.
class CommunityCalling::WatchdogJob < ApplicationJob
  queue_as :default
  retry_on CustomExceptions::CommunityCallingError, wait: 10.seconds, attempts: 3 do |job, _error|
    # Keep the reservation and retry cleanup after an outage instead of abandoning a live Meta call.
    Rails.logger.warn('[CommunityCalling] Remote cleanup is pending; retrying in 30 seconds')
    job.class.set(wait: 30.seconds).perform_later(*job.arguments)
  end

  def perform(call_id)
    call = CommunityWhatsappCall.find_by(id: call_id)
    return unless call&.ongoing?

    call.with_lock do
      return unless call.ongoing?

      expired = call.status == 'ringing' && call.created_at < 90.seconds.ago
      expired ||= call.user_id.present? && call.last_seen_at && call.last_seen_at < 60.seconds.ago
      if expired
        unless call.provider_call_id.start_with?('pending:')
          CommunityCalling::MetaClient.new(call.inbox.channel).control(call, call.direction == 'incoming' && call.status == 'ringing' ? 'reject' : 'terminate')
        end
        call.finish!(call.answered_at ? 'completed' : 'missed')
      else
        self.class.set(wait: 30.seconds).perform_later(call.id)
      end
    end
  end
end
