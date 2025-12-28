# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Diagram
    class StatesAdapter
      attr_reader :states

      # @rbs (Lrama::States) -> void
      def initialize(states)
        @states = states
      end

      # @rbs (name: String?) -> Automograph::Model
      def build(name: nil)
        model = Automograph::Model.new(name: name || "LALR(1) Automaton")

        build_states(model)
        build_transitions(model)

        model
      end

      private

      # @rbs (Automograph::Model) -> void
      def build_states(model)
        @states.states.each do |state|
          is_initial = state.id == 0
          is_accept = accepting_state?(state)

          model.add_state(
            state.id,
            label: "State #{state.id}",
            description: format_items(state),
            accept: is_accept,
            initial: is_initial,
            metadata: {
              items: state.items.map { |i| format_item(i) },
              conflicts: detect_conflicts(state)
            }
          )

          model.initial_state_id = state.id if is_initial
        end
      end

      # @rbs (Automograph::Model) -> void
      def build_transitions(model)
        @states.states.each do |state|
          # Shift transitions (terminal symbols)
          state.term_transitions.each do |shift|
            model.add_transition(
              from: state.id,
              to: shift.to_state.id,
              label: shift.next_sym.display_name,
              type: :shift
            )
          end

          # Goto transitions (nonterminal symbols)
          state.nterm_transitions.each do |goto|
            model.add_transition(
              from: state.id,
              to: goto.to_state.id,
              label: goto.next_sym.display_name,
              type: :goto
            )
          end
        end
      end

      # @rbs (Lrama::State) -> bool
      def accepting_state?(state)
        state.items.any? do |item|
          item.lhs.id.s_value == "$accept" && item.end_of_rule?
        end
      end

      # @rbs (Lrama::State) -> String
      def format_items(state)
        state.items.map { |i| format_item(i) }.join("\n")
      end

      # @rbs (Lrama::State::Item) -> String
      def format_item(item)
        lhs = item.lhs.display_name
        rhs = item.rhs.map(&:display_name)
        rhs.insert(item.position, "•")
        "#{lhs} → #{rhs.join(' ')}"
      end

      # @rbs (Lrama::State) -> Array[Hash[Symbol, untyped]]
      def detect_conflicts(state)
        conflicts = []

        # Shift/Reduce conflicts
        state.sr_conflicts.each do |conflict|
          conflicts << {
            type: :shift_reduce,
            symbols: conflict.symbols.map(&:display_name)
          }
        end

        # Reduce/Reduce conflicts
        state.rr_conflicts.each do |conflict|
          conflicts << {
            type: :reduce_reduce,
            symbols: conflict.symbols.map(&:display_name)
          }
        end

        conflicts
      end
    end
  end
end
