# https://docs.360dialog.com/whatsapp-api/whatsapp-api/media
# https://developers.facebook.com/docs/whatsapp/api/media/

class Whatsapp::IncomingMessageWhatsappCloudService < Whatsapp::IncomingMessageBaseService
  private

  def process_statuses
    @processed_params[:statuses].each { |receipt| CommunityCampaigns::StatusService.new(inbox, receipt).perform }
    super
  end

  def processed_params
    @processed_params ||= params[:entry].try(:first).try(:[], 'changes').try(:first).try(:[], 'value')
  end

  def create_messages
    super
    @campaign_reply&.delivery&.record_reply!(@message, @campaign_reply.source) if @message&.persisted?
  end

  def message_content_attributes(message)
    attributes = super
    return attributes if outgoing_echo

    # Contact cards build several messages from one webhook; attribute the webhook once.
    unless defined?(@campaign_reply)
      @campaign_reply = CommunityCampaigns::ReplyAttributionService.new(inbox: inbox, contact: @contact, message: message).perform
    end
    attributes[:campaign_attribution] = @campaign_reply.content_attributes if @campaign_reply
    attributes
  end

  def download_attachment_file(attachment_payload)
    url_response = HTTParty.get(
      inbox.channel.media_url(attachment_payload[:id]),
      headers: inbox.channel.api_headers
    )

    # This url response will be failure if the access token has expired.
    inbox.channel.authorization_error! if url_response.unauthorized?

    return unless url_response.success?

    downloaded_file = Down.download(url_response.parsed_response['url'], headers: inbox.channel.api_headers)
    # WhatsApp Cloud sends the original filename in the payload; preserve it so accented
    # names keep their correct extension instead of relying on the mangled remote metadata.
    filename = attachment_payload[:filename]
    downloaded_file.define_singleton_method(:original_filename) { filename } if filename.present?
    downloaded_file
  end
end
