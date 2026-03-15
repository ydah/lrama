# frozen_string_literal: true

RSpec.describe Lrama::LexerContextClassifier do
  include PslrFamilyHelper

  let(:classifier) { described_class.new }

  describe "context constants" do
    it "defines non-overlapping bitmask flags" do
      flags = [
        described_class::BEG,
        described_class::CMDARG,
        described_class::ARG,
        described_class::END_,
        described_class::ENDFN,
        described_class::MID,
        described_class::DOT,
      ]

      # All flags should be powers of 2
      flags.each do |flag|
        expect(flag).to be > 0
        expect(flag & (flag - 1)).to eq(0), "#{flag} is not a power of 2"
      end

      # No two flags should overlap
      flags.combination(2).each do |a, b|
        expect(a & b).to eq(0), "Flags #{a} and #{b} overlap"
      end
    end
  end

  describe ".context_name" do
    it "returns UNKNOWN for 0" do
      expect(described_class.context_name(0)).to eq("UNKNOWN")
    end

    it "returns single context name for single flag" do
      expect(described_class.context_name(described_class::BEG)).to eq("BEG")
      expect(described_class.context_name(described_class::CMDARG)).to eq("CMDARG")
      expect(described_class.context_name(described_class::END_)).to eq("END")
      expect(described_class.context_name(described_class::ENDFN)).to eq("ENDFN")
      expect(described_class.context_name(described_class::DOT)).to eq("DOT")
    end

    it "returns combined name for multiple flags" do
      combined = described_class::BEG | described_class::CMDARG
      name = described_class.context_name(combined)
      expect(name).to include("BEG")
      expect(name).to include("CMDARG")
    end
  end

  describe "#classify" do
    context "with a grammar that has distinguishable contexts" do
      let(:grammar) do
        build_grammar(<<~GRAMMAR, "lexer_context/basic.y")
          %define lr.type pslr
          %token-pattern IF /if/
          %token-pattern ID /[a-z]+/
          %lex-prec IF - ID

          %%

          program
            : expr
            ;

          expr
            : ID
            | expr '+' expr
            ;
        GRAMMAR
      end

      it "classifies states without errors" do
        states = Lrama::States.new(grammar, Lrama::Tracer.new(Lrama::Logger.new))
        states.compute
        states.compute_pslr

        # Every state should have a lexer_context assigned
        states.states.each do |state|
          expect(state.lexer_context).not_to be_nil
        end
      end
    end

    context "with operator-heavy grammar" do
      let(:grammar) do
        build_grammar(<<~GRAMMAR, "lexer_context/operators.y")
          %define lr.type pslr
          %token-pattern PLUS /\\+/
          %token-pattern STAR /\\*/
          %token-pattern ID /[a-z]+/
          %token-pattern NUM /[0-9]+/

          %%

          program
            : expr
            ;

          expr
            : NUM
            | ID
            | expr PLUS expr
            | expr STAR expr
            ;
        GRAMMAR
      end

      it "classifies all states" do
        states = Lrama::States.new(grammar, Lrama::Tracer.new(Lrama::Logger.new))
        states.compute
        states.compute_pslr

        states.states.each do |state|
          expect(state.lexer_context).not_to be_nil
        end

        # The initial state should have BEG context (beginning of program)
        initial_state = states.states.first
        expect(initial_state.lexer_context).not_to eq(0)
      end
    end

    context "with keyword context grammar" do
      let(:grammar) do
        build_grammar(<<~GRAMMAR, "lexer_context/keyword.y")
          %define lr.type pslr
          %token-pattern P /p/
          %token-pattern Q /q/
          %token-pattern X /x/
          %token-pattern IF /if/
          %token-pattern ID /[a-z]+/
          %lex-prec IF - ID

          %%

          program
            : kw_context
            | id_context
            ;

          kw_context
            : P shared IF
            ;

          id_context
            : Q shared ID
            ;

          shared
            : X
            ;
        GRAMMAR
      end

      it "classifies states and provides lexer context table" do
        states = Lrama::States.new(grammar, Lrama::Tracer.new(Lrama::Logger.new))
        states.compute
        states.compute_pslr

        table = states.lexer_context_table
        expect(table).to be_an(Array)
        expect(table.size).to eq(states.states_count)

        # All values should be non-negative integers
        table.each do |ctx|
          expect(ctx).to be_a(Integer)
          expect(ctx).to be >= 0
        end
      end
    end
  end

  describe "#infer_item_context" do
    context "with a simple grammar" do
      let(:grammar) do
        build_grammar(<<~GRAMMAR, "lexer_context/infer.y")
          %define lr.type pslr
          %token-pattern ID /[a-z]+/
          %token-pattern NUM /[0-9]+/

          %%

          program
            : expr
            ;

          expr
            : NUM
            | expr '+' expr
            ;
        GRAMMAR
      end

      it "classifies position-0 items as BEG" do
        states = Lrama::States.new(grammar, Lrama::Tracer.new(Lrama::Logger.new))
        states.compute
        states.compute_pslr

        # Find items at position 0
        states.states.each do |state|
          state.kernels.each do |item|
            if item.position == 0
              ctx = classifier.infer_item_context(item)
              expect(ctx).to eq(described_class::BEG)
            end
          end
        end
      end
    end
  end

  describe "integration with States" do
    context "lexer_context_enabled?" do
      it "returns false before compute_pslr" do
        grammar = build_grammar(<<~GRAMMAR, "lexer_context/enabled.y")
          %define lr.type pslr
          %token-pattern ID /[a-z]+/

          %%

          program : ID ;
        GRAMMAR

        states = Lrama::States.new(grammar, Lrama::Tracer.new(Lrama::Logger.new))
        states.compute

        expect(states.lexer_context_enabled?).to eq(false)
      end

      it "returns true after compute_pslr" do
        grammar = build_grammar(<<~GRAMMAR, "lexer_context/enabled.y")
          %define lr.type pslr
          %token-pattern ID /[a-z]+/

          %%

          program : ID ;
        GRAMMAR

        states = Lrama::States.new(grammar, Lrama::Tracer.new(Lrama::Logger.new))
        states.compute
        states.compute_pslr

        expect(states.lexer_context_enabled?).to eq(true)
      end
    end

    context "lexer_context_table" do
      it "returns an array with one entry per state" do
        grammar = build_grammar(<<~GRAMMAR, "lexer_context/table.y")
          %define lr.type pslr
          %token-pattern ID /[a-z]+/
          %token-pattern NUM /[0-9]+/

          %%

          program
            : expr
            ;

          expr
            : NUM
            | ID
            | expr '+' expr
            ;
        GRAMMAR

        states = Lrama::States.new(grammar, Lrama::Tracer.new(Lrama::Logger.new))
        states.compute
        states.compute_pslr

        table = states.lexer_context_table
        expect(table.size).to eq(states.states_count)
        expect(table.all? { |v| v.is_a?(Integer) }).to eq(true)
      end
    end
  end

  describe "terminal context classification" do
    it "classifies operator-like terminals as BEG" do
      # Operators mean we're at the beginning of the next expression
      %w[tPLUS tMINUS tSTAR tDSTAR tAMPER tLSHFT].each do |name|
        sym = double("symbol", id: double("id", s_value: name), term?: true)
        ctx = classifier.send(:classify_terminal_context, sym)
        expect(ctx).to eq(described_class::BEG), "Expected #{name} to be BEG, got #{described_class.context_name(ctx)}"
      end
    end

    it "classifies identifier terminals as CMDARG" do
      %w[tIDENTIFIER tFID tCONSTANT].each do |name|
        sym = double("symbol", id: double("id", s_value: name), term?: true)
        ctx = classifier.send(:classify_terminal_context, sym)
        expect(ctx).to eq(described_class::CMDARG), "Expected #{name} to be CMDARG, got #{described_class.context_name(ctx)}"
      end
    end

    it "classifies literal terminals as END" do
      %w[tINTEGER tFLOAT tSTRING_END tSYMBOL].each do |name|
        sym = double("symbol", id: double("id", s_value: name), term?: true)
        ctx = classifier.send(:classify_terminal_context, sym)
        expect(ctx).to eq(described_class::END_), "Expected #{name} to be END, got #{described_class.context_name(ctx)}"
      end
    end

    it "classifies keyword_def as ENDFN" do
      sym = double("symbol", id: double("id", s_value: "keyword_def"), term?: true)
      ctx = classifier.send(:classify_terminal_context, sym)
      expect(ctx).to eq(described_class::ENDFN)
    end

    it "classifies dot tokens as DOT" do
      %w[tDOT tCOLON2 tANDDOT].each do |name|
        sym = double("symbol", id: double("id", s_value: name), term?: true)
        ctx = classifier.send(:classify_terminal_context, sym)
        expect(ctx).to eq(described_class::DOT), "Expected #{name} to be DOT, got #{described_class.context_name(ctx)}"
      end
    end

    it "classifies open brackets as BEG" do
      %w[tLPAREN tLBRACK tLBRACE tLPAREN_ARG tLBRACE_ARG].each do |name|
        sym = double("symbol", id: double("id", s_value: name), term?: true)
        ctx = classifier.send(:classify_terminal_context, sym)
        expect(ctx).to eq(described_class::BEG), "Expected #{name} to be BEG, got #{described_class.context_name(ctx)}"
      end
    end

    it "classifies close brackets as END" do
      %w[tRPAREN tRBRACK tRBRACE].each do |name|
        sym = double("symbol", id: double("id", s_value: name), term?: true)
        ctx = classifier.send(:classify_terminal_context, sym)
        expect(ctx).to eq(described_class::END_), "Expected #{name} to be END, got #{described_class.context_name(ctx)}"
      end
    end

    it "classifies keyword_end as END" do
      sym = double("symbol", id: double("id", s_value: "keyword_end"), term?: true)
      ctx = classifier.send(:classify_terminal_context, sym)
      expect(ctx).to eq(described_class::END_)
    end

    it "classifies BEG keywords as BEG" do
      %w[keyword_if keyword_unless keyword_while keyword_until keyword_case
         keyword_for keyword_begin keyword_do keyword_return keyword_break
         keyword_class keyword_module].each do |name|
        sym = double("symbol", id: double("id", s_value: name), term?: true)
        ctx = classifier.send(:classify_terminal_context, sym)
        expect(ctx).to eq(described_class::BEG), "Expected #{name} to be BEG, got #{described_class.context_name(ctx)}"
      end
    end
  end

  describe "nonterminal context classification" do
    it "classifies expression-like nonterminals as END" do
      %w[expr arg primary literal].each do |name|
        sym = double("symbol", id: double("id", s_value: name), term?: false)
        ctx = classifier.send(:classify_nonterminal_context, sym)
        expect(ctx).to eq(described_class::END_), "Expected #{name} to be END, got #{described_class.context_name(ctx)}"
      end
    end

    it "classifies fname-like nonterminals as ENDFN" do
      %w[fname fsym].each do |name|
        sym = double("symbol", id: double("id", s_value: name), term?: false)
        ctx = classifier.send(:classify_nonterminal_context, sym)
        expect(ctx).to eq(described_class::ENDFN), "Expected #{name} to be ENDFN, got #{described_class.context_name(ctx)}"
      end
    end

    it "classifies command-like nonterminals as CMDARG" do
      %w[command fcall].each do |name|
        sym = double("symbol", id: double("id", s_value: name), term?: false)
        ctx = classifier.send(:classify_nonterminal_context, sym)
        expect(ctx).to eq(described_class::CMDARG), "Expected #{name} to be CMDARG, got #{described_class.context_name(ctx)}"
      end
    end

    it "classifies dot_or_colon as DOT" do
      sym = double("symbol", id: double("id", s_value: "dot_or_colon"), term?: false)
      ctx = classifier.send(:classify_nonterminal_context, sym)
      expect(ctx).to eq(described_class::DOT)
    end
  end

  describe "context-based state splitting" do
    context "with BEG vs CMDARG mixed context" do
      # This grammar creates a shared nonterminal reached from both
      # an operator context (BEG) and an identifier context (CMDARG).
      # The LALR automaton merges these into one state.
      # Context splitting should separate them.
      let(:grammar) do
        build_grammar(<<~GRAMMAR, "lexer_context/beg_vs_cmdarg.y")
          %define lr.type pslr
          %token-pattern tPLUS /\\+/
          %token-pattern tIDENTIFIER /[a-z]+/
          %token-pattern tINTEGER /[0-9]+/
          %token-pattern keyword_if /if/
          %lex-prec keyword_if - tIDENTIFIER

          %%

          program
            : expr
            ;

          expr
            : tINTEGER
            | tIDENTIFIER
            | expr tPLUS expr
            | expr keyword_if expr
            ;
        GRAMMAR
      end

      it "splits mixed-context states" do
        states = Lrama::States.new(grammar, Lrama::Tracer.new(Lrama::Logger.new))
        states.compute
        states.compute_pslr

        # After splitting, states that were reached from both
        # operator (BEG) and identifier (CMDARG) contexts should
        # have been separated into distinct states
        contexts_seen = states.states.map(&:lexer_context).uniq.reject { |c| c == 0 }
        expect(contexts_seen).not_to be_empty
      end
    end

    context "with operator vs identifier predecessor contexts" do
      let(:grammar) do
        build_grammar(<<~GRAMMAR, "lexer_context/split_expr.y")
          %define lr.type pslr
          %token-pattern tPLUS /\\+/
          %token-pattern tSTAR /\\*/
          %token-pattern tIDENTIFIER /[a-z]+/
          %token-pattern tINTEGER /[0-9]+/

          %%

          program
            : expr
            ;

          expr
            : tINTEGER
            | tIDENTIFIER
            | expr tPLUS expr
            | expr tSTAR expr
            ;
        GRAMMAR
      end

      it "classifies all states with non-nil context" do
        states = Lrama::States.new(grammar, Lrama::Tracer.new(Lrama::Logger.new))
        states.compute
        states.compute_pslr

        states.states.each do |state|
          expect(state.lexer_context).not_to be_nil,
            "State #{state.id} has nil lexer_context"
        end
      end

      it "has BEG context after operators" do
        states = Lrama::States.new(grammar, Lrama::Tracer.new(Lrama::Logger.new))
        states.compute
        states.compute_pslr

        # Find states after tPLUS or tSTAR
        operator_target_states = []
        states.states.each do |state|
          state.term_transitions.each do |shift|
            name = shift.next_sym.id.s_value
            if name == "tPLUS" || name == "tSTAR"
              operator_target_states << shift.to_state
            end
          end
        end

        operator_target_states.each do |target|
          ctx = target.lexer_context || 0
          expect(ctx & Lrama::LexerContextClassifier::BEG).not_to eq(0),
            "State #{target.id} after operator should have BEG context, got #{Lrama::LexerContextClassifier.context_name(ctx)}"
        end
      end
    end

    context "with def keyword creating ENDFN context" do
      let(:grammar) do
        build_grammar(<<~GRAMMAR, "lexer_context/endfn.y")
          %define lr.type pslr
          %token-pattern keyword_def /def/
          %token-pattern keyword_end /end/
          %token-pattern tIDENTIFIER /[a-z]+/
          %token-pattern tINTEGER /[0-9]+/

          %%

          program
            : defn
            ;

          defn
            : keyword_def tIDENTIFIER keyword_end
            ;
        GRAMMAR
      end

      it "marks state after keyword_def as ENDFN" do
        states = Lrama::States.new(grammar, Lrama::Tracer.new(Lrama::Logger.new))
        states.compute
        states.compute_pslr

        # Find state reached after keyword_def
        def_target = nil
        states.states.each do |state|
          state.term_transitions.each do |shift|
            if shift.next_sym.id.s_value == "keyword_def"
              def_target = shift.to_state
            end
          end
        end

        expect(def_target).not_to be_nil
        ctx = def_target.lexer_context || 0
        expect(ctx & Lrama::LexerContextClassifier::ENDFN).not_to eq(0),
          "State after keyword_def should have ENDFN context, got #{Lrama::LexerContextClassifier.context_name(ctx)}"
      end
    end
  end

  describe "existing PSLR tests still pass" do
    context "pure reduce profile" do
      let(:grammar) do
        build_grammar(<<~GRAMMAR, "states/pslr_pure_reduce.y")
          %define lr.type pslr
          %token-pattern RSHIFT />>/
          %token-pattern RANGLE />/
          %token-pattern ID /[a-z]+/
          %lex-prec RANGLE -s RSHIFT

          %%

          program
            : templ
            | rshift_expr
            ;

          templ
            : a RANGLE
            ;

          rshift_expr
            : a RSHIFT ID
            ;

          a
            : ID
            ;
        GRAMMAR
      end

      it "classifies states without breaking PSLR" do
        _, pslr_states = compute_ielr_and_pslr(grammar)

        expect(pslr_states.pslr_inadequacies).to be_empty

        # All states should have lexer context
        pslr_states.states.each do |state|
          expect(state.lexer_context).not_to be_nil
        end
      end
    end

    context "chained keyword split" do
      let(:grammar) do
        build_grammar(keyword_context_source(depth: 2), "states/pslr_keyword_ctx.y")
      end

      it "classifies states without breaking PSLR split" do
        ielr_states, pslr_states = compute_ielr_and_pslr(grammar)

        expect(pslr_states.states_count).to be > ielr_states.states_count
        expect(pslr_states.pslr_inadequacies).to be_empty

        pslr_states.states.each do |state|
          expect(state.lexer_context).not_to be_nil
        end
      end
    end
  end
end
