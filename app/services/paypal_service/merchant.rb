module PaypalService
  class Merchant

    include MerchantActions

    attr_reader :action_handlers

    def initialize(endpoint, api_credentials, logger, action_handlers = MERCHANT_ACTIONS, api_builder = nil)
      @logger = logger
      @api_builder = api_builder || self.method(:build_api)
      @action_handlers = action_handlers

      PayPal::SDK.configure(
        {
         mode: endpoint[:endpoint_name].to_s,
         username: api_credentials[:username],
         password: api_credentials[:password],
         signature: api_credentials[:signature],
         app_id: api_credentials[:app_id]
        }
      )
    end

    def do_request(request)
      action_def = @action_handlers[request[:method]]
      return exec_action(action_def, @api_builder.call(request), request) if action_def

      raise(ArgumentException, "Unknown request method #{request.method}")
    end


    def build_api(request)
      req = request.to_h
      if (req[:receiver_username])
        PayPal::SDK::Merchant.new(nil, { subject: req[:receiver_username] })
      else
        PayPal::SDK::Merchant.new
      end
    end


    private

    def exec_action(action_def, api, request)
      input_transformer = action_def[:input_transformer]
      wrapper_method = api.method(action_def[:wrapper_method_name])
      action_method = api.method(action_def[:action_method_name])
      output_transformer = action_def[:output_transformer]

      input = input_transformer.call(request)
      wrapped = wrapper_method.call(input)
      response = action_method.call(wrapped)

      @logger.log_response(response)
      if (response.success?)
        output_transformer.call(response, api)
      else
        create_failure_response(response)
      end
    end


    def create_failure_response(res)
      if (res.errors.length > 0)
        DataTypes.create_failure_response({
          error_code: res.errors[0].error_code,
          error_msg: res.errors[0].long_message
        })
      else
        DataTypes.create_failure_response({})
      end
    end
  end
end