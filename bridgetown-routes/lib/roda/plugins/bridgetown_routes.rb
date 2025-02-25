# frozen_string_literal: true

require "roda/plugins/flash"

Roda::RodaPlugins::Flash::FlashHash.include Bridgetown::Routes::FlashHashAdditions,
                                            Bridgetown::Routes::FlashHashIndifferent
Roda::RodaPlugins::Flash::FlashHash.class_eval do
  def initialize(hash = {})
    super(hash || {})
    now.singleton_class.include Bridgetown::Routes::FlashHashAdditions,
                                Bridgetown::Routes::FlashNowHashIndifferent
    @next = {}
  end
end

class Roda
  module RodaPlugins
    module BridgetownRoutes
      def self.load_dependencies(app)
        app.plugin :slash_path_empty # now /hello and /hello/ are both matched
        app.plugin :placeholder_string_matchers
        app.plugin :flash
        app.plugin :route_csrf, check_header: true
      end

      def self.configure(app, _opts = {})
        return unless app.opts[:bridgetown_site].nil?

        raise "Roda app failure: the bridgetown_ssr plugin must be registered before" \
              " bridgetown_routes"
      end

      module InstanceMethods
        def render_with(data: {}) # rubocop:todo Metrics/AbcSize, Metrics/MethodLength
          path = Kernel.caller_locations(1, 1).first.path
          source_path = Pathname.new(path).relative_path_from(
            Bridgetown::Current.site.in_source_dir("_routes")
          )
          code = response._route_file_code

          unless code.present?
            raise Bridgetown::Errors::FatalException,
                  "`render_with' method must be called from a template-based file in `src/_routes'"
          end

          data = Bridgetown::Model::BuilderOrigin.new(
            Bridgetown::Model::BuilderOrigin.id_for_builder_path(
              self, Addressable::URI.encode(source_path.to_s)
            )
          ).read do
            data[:_collection_] = Bridgetown::Current.site.collections.pages
            data[:_relative_path_] = source_path
            data[:_content_] = code
            data
          end

          Bridgetown::Model::Base.new(data).to_resource.tap do |resource|
            resource.roda_app = self
          end.read!.transform!.output
        end

        def render(...)
          view.render(...)
        end

        def view(view_class: Bridgetown::ERBView)
          response._fake_resource_view(
            view_class: view_class, roda_app: self, bridgetown_site: bridgetown_site
          )
        end
      end

      module ResponseMethods
        # template string provided, if available, by the saved code block
        def _route_file_code
          @_route_file_code
        end

        def _fake_resource_view(view_class:, roda_app:, bridgetown_site:)
          @_fake_resource_views ||= {}
          @_fake_resource_views[view_class] ||= view_class.new(
            # TODO: use a Stuct for better performance...?
            HashWithDotAccess::Hash.new({
              data: {},
              roda_app: roda_app,
              site: bridgetown_site,
            })
          )
        end
      end
    end

    register_plugin :bridgetown_routes, BridgetownRoutes
  end
end
