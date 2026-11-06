class Api::V1::Accounts::WorkspaceBrandingController < Api::V1::Accounts::BaseController
  before_action :authorize_branding

  def show
    render json: Current.account.workspace_branding.as_json
  end

  def update
    logo = params[:logo]
    if logo.present? && !valid_logo?(logo)
      return render json: { error: 'Elige una imagen PNG, JPG o WebP de máximo 2 MB.' }, status: :unprocessable_entity
    end

    branding = Current.account.workspace_branding
    attributes = params.permit(:name, :color, :website_url).to_h
    unless params.slice(:name, :color, :website_url).values.all? { |value| value.is_a?(String) }
      return render json: { error: 'El nombre, el color y el sitio web deben ser texto.' }, status: :unprocessable_entity
    end
    branding.save!(attributes, logo: logo, remove_logo: params[:remove_logo] == '1')
    render json: Current.account.workspace_branding.as_json
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join('. ') }, status: :unprocessable_entity
  end

  def destroy
    Current.account.workspace_branding.reset!
    render json: Current.account.workspace_branding.as_json
  end

  private

  def authorize_branding
    authorize Current.account, action_name == 'show' ? :show? : :update?
  end

  def valid_logo?(logo)
    return false unless logo.is_a?(ActionDispatch::Http::UploadedFile) && logo.size <= WorkspaceBranding::MAX_LOGO_SIZE

    WorkspaceBranding::LOGO_CONTENT_TYPES.include?(Marcel::MimeType.for(logo.tempfile))
  end
end
