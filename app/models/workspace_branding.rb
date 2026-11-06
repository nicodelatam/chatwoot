# Independent workspace identity for Community Edition.
class WorkspaceBranding
  include ActiveModel::Model

  DEFAULTS = {
    'name' => 'Ni.CO', 'color' => '#E30613', 'website_url' => 'https://nicodelatam.com',
    'logo_url' => '/branding/nico-mark.svg'
  }.freeze
  LOGO_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
  MAX_LOGO_SIZE = 2.megabytes

  attr_accessor :name, :color, :website_url
  attr_reader :account

  validates :name, presence: true, length: { maximum: 80 }
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }
  validate :valid_website_url

  def initialize(account = nil)
    @account = account
    super(DEFAULTS.slice('name', 'color', 'website_url').merge(account&.settings&.fetch('workspace_branding', {}) || {}))
  end

  def as_json(*)
    {
      name: name, color: color, website_url: website_url, logo_url: logo_url,
      customized: account&.settings&.key?('workspace_branding') || account&.workspace_brand_logo&.attached? || false,
      login_url: login_url
    }
  end

  def logo_url
    return DEFAULTS['logo_url'] unless account&.workspace_brand_logo&.attached?

    Rails.application.routes.url_helpers.rails_blob_path(account.workspace_brand_logo, only_path: true)
  end

  def login_url
    base = ENV.fetch('FRONTEND_URL', '').delete_suffix('/')
    return "#{base}/app/login" unless account

    "#{base}/app/login?workspace=#{CGI.escape(account.signed_id(purpose: :workspace_branding))}"
  end

  def global_config
    {
      'INSTALLATION_NAME' => name, 'BRAND_NAME' => name, 'BRAND_URL' => website_url,
      'WIDGET_BRAND_URL' => website_url, 'LOGO' => logo_url, 'LOGO_DARK' => logo_url,
      'LOGO_THUMBNAIL' => logo_url, 'WORKSPACE_BRANDING' => as_json,
      'BRAND_COLOR' => color
    }
  end

  def save!(attributes, logo: nil, remove_logo: false)
    assign_attributes(attributes)
    raise ActiveRecord::RecordInvalid, self unless valid?

    removed_blob = account.workspace_brand_logo.blob if remove_logo && !logo
    account.with_lock do
      account.settings = account.settings.merge('workspace_branding' => { 'name' => name.strip, 'color' => color, 'website_url' => website_url })
      account.workspace_brand_logo.detach if remove_logo && !logo
      account.workspace_brand_logo.attach(logo) if logo
      account.save!
    end
    removed_blob&.purge_later
  end

  def reset!
    removed_blob = account.workspace_brand_logo.blob
    account.with_lock do
      account.settings = account.settings.except('workspace_branding')
      account.workspace_brand_logo.detach
      account.save!
    end
    removed_blob&.purge_later
  end

  private

  def valid_website_url
    return if website_url.blank?

    uri = URI.parse(website_url)
    errors.add(:base, 'Usa una dirección web con https:// o http://.') unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    errors.add(:base, 'Usa una dirección web con https:// o http://.')
  end
end
