# -*- encoding : utf-8 -*-
module Taobao
  class Client
    def self.execute(params)
      sign_params = Param.new(params).to_param
      api_name = sign_params[:method].split('.')[1..-1]
      if api_name.last == 'get'
        body = RestClient.get(TaobaoConfig.api_site, :params => sign_params)
      else
        body = RestClient.post(TaobaoConfig.api_site, sign_params)
      end
      result_hash = MultiJson.load(body)
      response_key = "#{api_name.join('_')}_response"
      if result_hash.key?(response_key)
        result_hash[response_key]
      elsif result_hash.key?('error_response')
        raise(ResponseError, result_hash['error_response'])
      else
        raise(UnknownError, body)
      end
    end
  end
end
