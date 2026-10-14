class CommunityCalling::ConfigurationService
  def initialize(channel)
    @channel = channel
  end

  def perform(enabled)
    enabled ? enable : disable
    persist_configuration(enabled)
  end

  private

  def enable
    if @channel.provider_config['calling_enabled']
      raise CustomExceptions::CommunityCallingError,
            'Disable Enterprise calling on this inbox before enabling community calling.'
    end

    validate_app_secret!
    CommunityCalling::MetaClient.new(@channel).enable
  end

  def disable
    if CommunityWhatsappCall.ongoing.exists?(inbox_id: @channel.inbox.id)
      raise CustomExceptions::CommunityCallingError, 'End the calls in this inbox before disabling calling.'
    end

    return unless @channel.provider_config['community_calling_enabled'] == true

    CommunityCalling::MetaClient.new(@channel).disable
  end

  def validate_app_secret!
    secret = MetaTokenVerifyConcern::CHANNEL_APP_SECRET_KEYS.any? do |key|
      @channel.provider_config[key].present?
    end
    return if secret || GlobalConfigService.load('WHATSAPP_APP_SECRET', nil).present?

    raise CustomExceptions::CommunityCallingError,
          'Configure the Meta app secret before enabling calling so incoming webhooks can be verified.'
  end

  def persist_configuration(enabled)
    @channel.provider_config = @channel.provider_config.merge('community_calling_enabled' => enabled)
    # The pending flag is visible to the shared WABA subscription setup before it is persisted.
    Whatsapp::WebhookSetupService.new(@channel).register_callback
    @channel.save!(validate: false)
  end
end
