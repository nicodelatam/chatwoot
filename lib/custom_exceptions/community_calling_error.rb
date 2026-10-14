class CustomExceptions::CommunityCallingError < StandardError
  attr_reader :code

  def initialize(message, code = 'calling_error')
    @code = code
    super(message)
  end
end
