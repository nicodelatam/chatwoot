class Api::V1::Accounts::CommunityCampaignStatisticsController < Api::V1::Accounts::BaseController
  before_action :authorize_statistics

  def show
    filters = report_filters
    return unless filters

    render json: CommunityCampaignReport.dashboard_for(Current.account, filters)
  end

  private

  def authorize_statistics
    raise Pundit::NotAuthorizedError unless current_user.is_a?(User)

    authorize Campaign, :index?
  end

  def report_filters
    timezone = params[:timezone].presence || 'America/Bogota'
    zone = timezone.is_a?(String) && ActiveSupport::TimeZone[timezone]
    raise CustomExceptions::CommunityCampaignFilterError, 'La zona horaria no es válida.' unless zone

    from = Date.iso8601(params[:from].presence || (zone.today - 29).iso8601)
    to = Date.iso8601(params[:to].presence || zone.today.iso8601)
    unless from <= to && (to - from) <= 365
      raise CustomExceptions::CommunityCampaignFilterError, 'Elige un rango de hasta 366 días, con la fecha inicial antes de la final.'
    end

    status = params[:status].presence || 'all'
    unless (CommunityCampaignDelivery::STATUSES + %w[all awaiting accepted delivered_all replied]).include?(status)
      raise CustomExceptions::CommunityCampaignFilterError, 'El estado no es válido.'
    end
    query = params[:query].presence || ''
    unless query.is_a?(String) && query.length <= 100
      raise CustomExceptions::CommunityCampaignFilterError, 'La búsqueda debe ser texto de hasta 100 caracteres.'
    end

    ids = params[:label_ids] || []
    unless ids.is_a?(Array) && ids.length <= 50
      raise CustomExceptions::CommunityCampaignFilterError, 'Las etiquetas deben ser una lista de identificadores.'
    end

    { zone: zone, from: from, to: to, status: status, query: query,
      campaign_id: params[:campaign_id].present? ? positive_id(params[:campaign_id]) : nil,
      label_ids: ids.map { |id| positive_id(id) }, page: positive_id(params[:page].presence || '1') }
  rescue CustomExceptions::CommunityCampaignFilterError => e
    render json: { error: e.message }, status: :unprocessable_entity
    nil
  rescue ArgumentError, TypeError
    render json: { error: 'Revisa las fechas, la zona horaria y los filtros seleccionados.' }, status: :unprocessable_entity
    nil
  end

  def positive_id(value)
    unless value.is_a?(String) && value.match?(/\A[1-9]\d{0,8}\z/)
      raise CustomExceptions::CommunityCampaignFilterError, 'El identificador no es válido.'
    end

    value.to_i
  end
end
