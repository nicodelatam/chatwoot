# Independent campaign transport using the existing MIT Cloud API adapter.
class CommunityCampaigns::CloudProvider < Whatsapp::Providers::WhatsappCloudService
  def send_template(identifier, template_info, delivery)
    response = HTTParty.post(
      "#{phone_id_path('v24.0')}/messages",
      headers: api_headers,
      timeout: 30,
      # Pin the inbox's Messaging account, as the base provider does, so Meta never bills another account on the number.
      body: { messaging_product: 'whatsapp', messaging_account_id: whatsapp_channel.provider_config['business_account_id'],
              **recipient_params(identifier), type: 'template',
              template: template_body_parameters(template_info),
              biz_opaque_callback_data: "community_campaign:#{delivery.signed_id(purpose: :community_campaign_receipt)}" }.to_json
    )
    process_response(response, delivery)
  end

  private

  def handle_error(response, delivery)
    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] || {} : {}
    message = error.dig('error_data', 'details').presence || error['message'].presence || 'WhatsApp rechazó el envío.'
    delivery.fail!(error['code']&.to_s || 'provider_error', message)
  end
end
