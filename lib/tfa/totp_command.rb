module TFA
  class TotpCommand
    def initialize(storage)
      @storage = storage
    end

    def run(name, secret = secret_for(name))
      secret ? password_for(secret) : all_passwords
    end

    private

    def password_for(secret)
      ::ROTP::TOTP.new(secret).now
    rescue ROTP::Base32::Base32Error
      "INVALID SECRET"
    end

    def all_passwords
      @storage.each do |hash|
        hash[hash.keys.first] = password_for(hash[hash.keys.first])
      end
    end

    def secret_for(key)
      @storage.secret_for(key)
    end
  end
end
