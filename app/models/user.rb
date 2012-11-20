class User < ActiveRecord::Base
  devise :database_authenticatable, :encryptable, :omniauthable

  attr_accessible :username, :provider, :uid, :access_token, :email

  @graph = false

  has_one :profile
  has_one :location

  validates :email,              presence: true, uniqueness: true
  validates :username,           presence: true, uniqueness: true
  validates :uid,                presence: true, :uniqueness => { scope: [:provider] }
  validates :provider,           presence: true

  def graph
    @graph ||= Koala::Facebook::API.new(self.access_token)
  end

  def post_location(ip_address=nil)
    user_location = self.location.present? ? self.location : self.build_location

    geo_data = graph.get_object('me', fields: 'location')['location']
    user_location.address = geo_data['name'] if geo_data.present?

    if !user_location.address.present? && ip_address.present?
      geo_data = Geokit::Geocoders::MultiGeocoder.geocode(ip_address)
      user_location.address = geo_data.full_address if geo_data.success
    end

    return user_location.save if user_location.address.present?
    false
  end

  def self.find_for_facebook_oauth(auth, signed_in_resource=nil)
    user = User.where(provider: auth.provider, uid: auth.uid).first
    user_hash = {
        username:     auth.extra.raw_info.username,
        provider:     auth.provider,
        uid:          auth.uid,
        access_token: auth.credentials.token,
        email:        auth.extra.raw_info.email
    }
    profile_hash = {
        name:     auth.extra.raw_info.name,
        logo:     auth.info.image,
        link:     auth.extra.raw_info.link,
        gender:   auth.extra.raw_info.gender,
        birthday: Date.strptime(auth.extra.raw_info.birthday, "%m/%d/%Y")
    }
    unless user
      user = User.new(user_hash)
      user.password = Devise.friendly_token[4,20]
      user.build_profile(profile_hash)
      user.save
    else
      user.update_attributes(user_hash)
      user.profile.update_attributes(profile_hash) if user.profile.present?
    end
    user
  end
end
