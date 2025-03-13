# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Tracer
    module Duration
      # TODO: rbs-inline 0.10.0 doesn't support instance variables.
      #       Move these type declarations above instance variable definitions, once it's supported.
      #
      # @rbs!
      #   @_report_duration_enabled: bool

      # @rbs () -> void
      def self.enable
        @_report_duration_enabled = true
      end

      # @rbs () -> bool
      def self.enabled?
        !!@_report_duration_enabled
      end

      # @rbs [T] (_ToS method_name) { -> T } -> T
      def report_duration(method_name)
        time1 = Time.now.to_f
        result = yield
        time2 = Time.now.to_f

        if Duration.enabled?
          STDERR.puts sprintf("%s %10.5f s", method_name, time2 - time1)
        end

        return result
      end
    end
  end
end
