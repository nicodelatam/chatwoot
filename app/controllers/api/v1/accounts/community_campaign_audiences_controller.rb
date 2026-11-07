class Api::V1::Accounts::CommunityCampaignAudiencesController < Api::V1::Accounts::BaseController
  before_action :authorize_audience

  def create
    unless params[:inbox_id].is_a?(Integer) && params[:inbox_id].positive? &&
           (params[:exclude_campaign_id].nil? || (params[:exclude_campaign_id].is_a?(Integer) && params[:exclude_campaign_id].positive?))
      raise CustomExceptions::CommunityCampaignFilterError, 'Los identificadores deben ser números enteros positivos.'
    end
    inbox = Current.account.inboxes.find(params[:inbox_id])
    unless params[:audience].is_a?(ActionController::Parameters) && params[:timezone].is_a?(String)
      raise CustomExceptions::CommunityCampaignFilterError, 'Revisa la audiencia y la zona horaria.'
    end
    zone = ActiveSupport::TimeZone[params[:timezone]]
    raise CustomExceptions::CommunityCampaignFilterError, 'La zona horaria no es válida.' unless zone

    selection = params[:audience].to_unsafe_h
    ids = selection.delete('label_ids') || []
    unless ids.is_a?(Array) && ids.size <= 50
      raise CustomExceptions::CommunityCampaignFilterError, 'Las etiquetas deben ser una lista de identificadores.'
    end
    candidate = Current.account.campaigns.new(inbox: inbox, audience: ids.map { |id| { 'id' => id, 'type' => 'Label' } },
                                            trigger_rules: { 'community_audience' => selection })
    if params[:exclude_campaign_id].present?
      candidate.id = Current.account.campaigns.find_by!(display_id: params[:exclude_campaign_id]).id
    end
    scheduled_at = params[:scheduled_at].present? ? Time.iso8601(params[:scheduled_at]) : Time.current
    render json: CommunityCampaigns::Audience.new(candidate).preview(zone: zone, scheduled_at: scheduled_at)
  rescue CustomExceptions::CommunityCampaignFilterError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ArgumentError, TypeError
    render json: { error: 'Revisa las fechas y los filtros de audiencia.' }, status: :unprocessable_entity
  end

  private

  def authorize_audience
    raise Pundit::NotAuthorizedError unless current_user.is_a?(User)

    authorize Campaign, :create?
  end
end
