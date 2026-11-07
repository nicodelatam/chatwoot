class CommunityCampaigns::SendDeliveryService
  def initialize(campaign, contact)
    @campaign = campaign
    @contact = contact
    @delivery = campaign.community_campaign_deliveries.find_by!(contact_id: contact.id)
  end

  def perform
    return unless @delivery.claim_send!
    return @delivery.fail!('contact_blocked', 'El contacto está bloqueado.') if @contact.blocked?

    recipient = destination
    return @delivery.fail!('missing_recipient', 'El contacto no tiene un destino de WhatsApp único.') if recipient.blank?
    return @delivery.fail!('missing_template', 'La campaña no tiene una plantilla configurada.') if @campaign.template_params.blank?

    params = Whatsapp::LiquidTemplateProcessorService.new(campaign: @campaign, contact: @contact).process_template_params(@campaign.template_params)
    return @delivery.fail!('template_variables', 'La plantilla tiene variables vacías para este contacto.') if params.blank?

    channel = @campaign.inbox.channel
    error = Whatsapp::AuthenticationTemplateGuard.new(channel: channel, recipient: recipient, template_params: params).error
    return @delivery.fail!('unsupported_recipient', error) if error.present?

    name, namespace, language, parameters = Whatsapp::TemplateProcessorService.new(channel: channel, template_params: params).call
    return @delivery.fail!('invalid_template', 'No se pudo preparar la plantilla de WhatsApp.') if name.blank?

    sending = true
    message_id = CommunityCampaigns::CloudProvider.new(whatsapp_channel: channel).send_template(
      recipient, { name: name, namespace: namespace, lang_code: language, parameters: parameters }, @delivery
    )
    @delivery.accept!(message_id) if message_id.present?
  rescue StandardError => e
    # An interrupted request can already have reached Meta. Never automatically resend it.
    @delivery.fail!(sending ? 'send_unconfirmed' : 'preparation_error',
                    sending ? 'No se pudo confirmar el envío con WhatsApp.' : 'No se pudo preparar el envío.', uncertain: !!sending)
    Rails.logger.error "[COMMUNITY_CAMPAIGN] delivery_id=#{@delivery.id} error=#{e.class.name}"
  end

  private

  def destination
    return @contact.phone_number if @contact.phone_number.present?

    identities = @contact.contact_inboxes.where(inbox_id: @campaign.inbox_id).pluck(:source_id).select do |source_id|
      source_id.to_s.delete_prefix('whatsapp:').match?(RegexHelper::WHATSAPP_BSUID_REGEX)
    end.uniq
    identities.first if identities.one?
  end
end
