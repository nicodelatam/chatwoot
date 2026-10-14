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
      next unless call.ongoing?

      expire_call(call) if expired?(call)
      schedule_next_check(call) if call.ongoing?
    end
  end

  private

  def expired?(call)
    ringing_call_expired?(call) || browser_session_expired?(call)
  end

  def ringing_call_expired?(call)
    call.status == 'ringing' && call.created_at < 90.seconds.ago
  end

  def browser_session_expired?(call)
    call.user_id.present? && call.last_seen_at && call.last_seen_at < 60.seconds.ago
  end

  def expire_call(call)
    terminate_remote_call(call) unless call.provider_call_id.start_with?('pending:')
    call.finish!(call.answered_at ? 'completed' : 'missed')
  end

  def terminate_remote_call(call)
    action = call.direction == 'incoming' && call.status == 'ringing' ? 'reject' : 'terminate'
    CommunityCalling::MetaClient.new(call.inbox.channel).control(call, action)
  end

  def schedule_next_check(call)
    self.class.set(wait: 30.seconds).perform_later(call.id)
  end
end
