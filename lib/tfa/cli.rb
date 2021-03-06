require 'rqrcode'
require 'socket'
require 'thor'
require 'uri'

module TFA
  class CLI < Thor
    package_name "TFA"
    class_option :filename
    class_option :directory
    class_option :passphrase

    desc "add NAME SECRET", "add a new secret to the database"
    def add(name, secret)
      storage.save(name, clean(secret))
      "Added #{name}"
    end

    desc "destroy NAME", "remove the secret associated with the name"
    def destroy(name)
      storage.delete(name)
    end

    desc "show NAME", "shows the secret for the given key"
    method_option :format, default: "raw", enum: ["raw", "qrcode", "uri"], desc: "The format to export"
    def show(name = nil)
      return storage.all.map { |x| x.keys }.flatten.sort unless name

      case options[:format]
      when "qrcode"
        RQRCode::QRCode.new(uri_for(name, storage.secret_for(name))).as_ansi(
          light: "\033[47m", dark: "\033[40m", fill_character: '  ', quiet_zone_size: 1
        )
      when "uri"
        uri_for(name, storage.secret_for(name))
      else
        storage.secret_for(name)
      end
    end

    desc "totp NAME", "generate a Time based One Time Password using the secret associated with the given NAME."
    def totp(name)
      TotpCommand.new(storage).run(name)
    end

    desc "now SECRET", "generate a Time based One Time Password for the given secret"
    def now(secret)
      TotpCommand.new(storage).run('', secret)
    end

    desc "upgrade", "upgrade the database."
    def upgrade
      if !File.exist?(pstore_path)
        say_status :error, "Unable to detect #{pstore_path}", :red
        return
      end
      if File.exist?(secure_path)
        say_status :error, "The new database format was detected.", :red
        return
      end

      if yes? "Upgrade to #{secure_path}?"
        secure_storage
        pstore_storage.each do |row|
          row.each do |name, secret|
            secure_storage.save(name, secret) if yes?("Migrate `#{name}`?")
          end
        end
        File.delete(pstore_path) if yes?("Delete `#{pstore_path}`?")
      end
    end

    desc "encrypt", "encrypts the tfa database"
    def encrypt
      return unless ensure_upgraded!

      secure_storage.encrypt!
    end

    desc "decrypt", "decrypts the tfa database"
    def decrypt
      return unless ensure_upgraded!

      secure_storage.decrypt!
    end

    private

    def storage
      File.exist?(pstore_path) ? pstore_storage : secure_storage
    end

    def pstore_storage
      @pstore_storage ||= Storage.new(pstore_path)
    end

    def secure_storage
      @secure_storage ||= SecureStorage.new(Storage.new(secure_path), ->{ passphrase })
    end

    def filename
      options[:filename] || '.tfa'
    end

    def directory
      options[:directory] || Dir.home
    end

    def pstore_path
      File.join(directory, "#{filename}.pstore")
    end

    def secure_path
      File.join(directory, filename)
    end

    def clean(secret)
      if secret.include?("=")
        /secret=([^&]*)/.match(secret).captures.first
      else
        secret
      end
    end

    def passphrase
      @passphrase ||=
        begin
          result = options[:passphrase] || ask("Enter passphrase:\n", echo: false)
          raise "Invalid Passphrase" if result.nil? || result.strip.empty?
          result
        end
    end

    def ensure_upgraded!
      return true if upgraded?

      error = "Use the `upgrade` command to upgrade your database."
      say_status :error, error, :red
      false
    end

    def upgraded?
      !File.exist?(pstore_path) && File.exist?(secure_path)
    end

    def uri_for(issuer, secret)
      URI.encode("otpauth://totp/#{issuer}/#{ENV['LOGNAME']}@#{Socket.gethostname}?secret=#{secret}&issuer=#{issuer}")
    end
  end
end
