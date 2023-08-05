require 'drb'

module God

  # The God::Server oversees the DRb server which dishes out info on this God daemon.
  class Socket
    attr_reader :path

    # The location of the socket for a given path
    #
    # Returns String (file location)
    def self.socket_file(path)
      path || God::DRB_SOCKET_DEFAULT
    end

    # The address of the socket for a given path
    #
    # Returns String (drb address)
    def self.socket(path)
      "drbunix://#{self.socket_file(path)}"
    end

    # The location of the socket for this Server
    #
    # Returns String (file location)
    def socket_file
      self.class.socket_file(@socket)
    end

    # The address of the socket for this Server
    #
    # Returns String (drb address)
    def socket
      self.class.socket(@socket)
    end

    # Create a new Server and star the DRb server
    def initialize(socket = nil, user = nil, group = nil, perm = nil)
      @socket = socket
      @user  = user
      @group = group
      @perm  = perm
      start
    end

    # Returns true
    def ping
      true
    end

    # Forward API calls to God
    #
    # Returns whatever the forwarded call returns
    def method_missing(*args, &block)
      God.send(*args, &block)
    end

    # Stop the DRb server and delete the socket file
    #
    # Returns nothing
    def stop
      DRb.stop_service
      FileUtils.rm_f(self.socket_file)
    end

    private

    # Start the DRb server. Abort if there is already a running god instance
    # on the socket.
    #
    # Returns nothing
    def start
      begin
        @drb ||= DRb.start_service(self.socket, self)
        applog(nil, :info, "Started on #{DRb.uri}")
      rescue Errno::EADDRINUSE
        applog(nil, :info, "Socket already in use")
        server = DRbObject.new(nil, self.socket)

        begin
          Timeout.timeout(5) do
            server.ping
          end
          abort "Socket #{self.socket} already in use by another instance of god"
        rescue StandardError, Timeout::Error
          applog(nil, :info, "Socket is stale, reopening")
          File.delete(self.socket_file) rescue nil
          @drb ||= DRb.start_service(self.socket, self)
          applog(nil, :info, "Started on #{DRb.uri}")
        end
      end

      if File.exist?(self.socket_file)
        if @user
          user_method = @user.is_a?(Integer) ? :getpwuid : :getpwnam
          uid = Etc.send(user_method, @user).uid
          gid = Etc.send(user_method, @user).gid
        end
        if @group
          group_method = @group.is_a?(Integer) ? :getgrgid : :getgrnam
          gid = Etc.send(group_method, @group).gid
        end

        File.chmod(Integer(@perm), socket_file) if @perm
        File.chown(uid, gid, socket_file) if uid or gid
      end
    end
  end

end
