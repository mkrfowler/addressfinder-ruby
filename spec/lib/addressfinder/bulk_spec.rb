require 'spec_helper'

RSpec.describe AddressFinder::Bulk do
  before do
    AddressFinder.configure do |af|
      af.api_key = 'XXX'
      af.api_secret = 'YYY'
      af.default_country = 'nz'
      af.timeout = 5
      af.retries = 1
    end
  end

  describe '#perform' do
    let(:http){ AddressFinder::HTTP.new(AddressFinder.configuration) }
    let(:net_http){ http.send(:net_http) }

    before do
      allow(http).to receive(:sleep)
      WebMock.allow_net_connect!(net_http_connect_on_start: true)
    end

    after do
      WebMock.disable_net_connect!
    end

    context "with 3 requests in the provided block" do
      let(:response){ double(:response, body: %Q({"success": true}), code: "200") }
      let(:block){
        Proc.new do |proxy|
          proxy.cleanse(q: "1 Willis")
          proxy.cleanse(q: "2 Willis")
          proxy.cleanse(q: "3 Willis")
        end
      }

      it "uses 1 http connection" do
        expect(net_http).to receive(:do_start).once.and_call_original
        expect(net_http).to receive(:transport_request).exactly(3).times.and_return(response)
        expect(net_http).to receive(:do_finish).once.and_call_original
        AddressFinder::Bulk.new(http: http, &block).perform
      end

      it "renews the http connection and continues where we left off when a Net::OpenTimeout error is raised" do
        expect(net_http).to receive(:do_start).twice.and_call_original
        expect(net_http).to receive(:transport_request).once.and_return(response) # 1 Willis (success)
        expect(net_http).to receive(:transport_request).once.and_raise(Net::OpenTimeout) # 2 Willis (error)
        expect(net_http).to receive(:transport_request).exactly(2).and_return(response) # Retry 2 Willis (success) & 3 Willis (success)
        expect(net_http).to receive(:do_finish).twice.times.and_call_original
        AddressFinder::Bulk.new(http: http, &block).perform
      end
    end
  end
end