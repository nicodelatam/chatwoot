# Independent integration with Meta's public WhatsApp Business Calling API.
# https://developers.facebook.com/documentation/business-messaging/whatsapp/calling/reference
class CommunityCalling::MetaClient
  def initialize(channel)
    @channel = channel
  end

  def settings
    request(:get, 'settings')
  end

  def enable
    if settings.dig('calling', 'sip', 'status') == 'ENABLED'
      raise CustomExceptions::CommunityCallingError,
            'SIP is enabled on this number. Use a separate Cloud API number for browser calling.'
    end

    request(:post, 'settings', calling: { status: 'ENABLED' })
  end

  def disable
    request(:post, 'settings', calling: { status: 'DISABLED' })
  end

  def permission(source_id)
    query = recipient(source_id, phone_key: :user_wa_id)
    request(:get, 'call_permissions', query)
  end

  def request_permission(source_id)
    payload = {
      messaging_product: 'whatsapp', recipient_type: 'individual', **recipient(source_id), type: 'interactive',
      interactive: {
        type: 'call_permission_request', action: { name: 'call_permission_request' },
        body: { text: I18n.t('community_calling.permission_request') }
      }
    }
    request(:post, 'messages', payload)
  end

  def connect(source_id, sdp, callback_data)
    request(:post, 'calls', messaging_product: 'whatsapp', **recipient(source_id), action: 'connect',
                            session: { sdp_type: 'offer', sdp: sdp }, biz_opaque_callback_data: callback_data)
  end

  def control(call, action, sdp: nil)
    payload = { messaging_product: 'whatsapp', call_id: call.provider_call_id, action: action }
    payload[:session] = { sdp_type: 'answer', sdp: sdp } if sdp
    request(:post, 'calls', payload)
  end

  private

  def recipient(source_id, phone_key: :to)
    source_id.match?(/\A\d+\z/) ? { phone_key => source_id } : { recipient: source_id }
  end

  def request(method, path, payload = {})
    options = {
      headers: {
        'Authorization' => "Bearer #{@channel.provider_config.fetch('api_key')}",
        'Content-Type' => 'application/json'
      },
      timeout: 10
    }
    options[method == :get ? :query : :body] = method == :get ? payload : payload.to_json
    base = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    url = "#{base}/v24.0/#{@channel.provider_config.fetch('phone_number_id')}/#{path}"
    response = HTTParty.public_send(method, url, options)
    parse_response(response)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError
    message = 'Meta could not be reached. Check the call status before trying again.'
    raise CustomExceptions::CommunityCallingError.new(message, 'meta_unavailable')
  end

  def parse_response(response)
    return response.parsed_response if response.success?

    code = response.parsed_response.dig('error', 'code') if response.parsed_response.is_a?(Hash)
    message = "Meta rejected the calling request (HTTP #{response.code}, code #{code}). " \
              'Check number eligibility, permissions and calling settings.'
    raise CustomExceptions::CommunityCallingError.new(message, 'meta_error')
  end
end
