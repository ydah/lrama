# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  # Classifies parser states into lexer context categories.
  #
  # When LALR states are merged, states from different grammatical contexts
  # (e.g., BEG vs CMDARG) share the same state number, making them
  # indistinguishable to the lexer. This classifier analyzes kernel items
  # to determine the lexer context of each state, enabling context-aware
  # state splitting.
  class LexerContextClassifier
    # Context flag constants (bitmask)
    BEG    = 0x01  # Beginning of expression (after operator, open paren, keyword, etc.)
    CMDARG = 0x02  # Command argument position (after identifier/method name)
    ARG    = 0x04  # Argument position (after open paren in method call)
    END_   = 0x08  # End of expression (after literal, close paren, identifier)
    ENDFN  = 0x10  # After method name in def (def method_name .)
    MID    = 0x20  # Mid-expression (after return/break/next)
    DOT    = 0x40  # After dot (method chain)

    CONTEXT_NAMES = {
      BEG    => "BEG",
      CMDARG => "CMDARG",
      ARG    => "ARG",
      END_   => "END",
      ENDFN  => "ENDFN",
      MID    => "MID",
      DOT    => "DOT",
    }.freeze

    # @rbs () -> void
    def initialize
      @terminal_context_cache = {}
      @nonterminal_context_cache = {}
    end

    # Classify a state's kernel items into context groups.
    #
    # @rbs (State state) -> Hash[Integer, Array[State::Item]]
    def classify(state)
      groups = {}

      state.kernels.each do |item|
        ctx = infer_item_context(item)
        groups[ctx] ||= []
        groups[ctx] << item
      end

      groups
    end

    # Infer the lexer context for a single kernel item.
    #
    # @rbs (State::Item item) -> Integer
    def infer_item_context(item)
      # Position 0 means we're at the start of a rule (just entered via GOTO)
      # The context depends on what the parent rule looks like
      return BEG if item.position == 0

      prev_sym = item.rhs[item.position - 1]
      if prev_sym.term?
        classify_terminal_context(prev_sym)
      else
        classify_nonterminal_context(prev_sym)
      end
    end

    # Classify context based on the terminal symbol before the dot.
    #
    # @rbs (Grammar::Symbol sym) -> Integer
    def classify_terminal_context(sym)
      @terminal_context_cache[sym.id.s_value] ||= compute_terminal_context(sym)
    end

    # Classify context based on the nonterminal symbol before the dot.
    #
    # @rbs (Grammar::Symbol sym) -> Integer
    def classify_nonterminal_context(sym)
      @nonterminal_context_cache[sym.id.s_value] ||= compute_nonterminal_context(sym)
    end

    # Return a human-readable name for a context value.
    #
    # @rbs (Integer ctx) -> String
    def self.context_name(ctx)
      return "UNKNOWN" if ctx == 0

      names = CONTEXT_NAMES.select { |flag, _| (ctx & flag) != 0 }.values
      names.empty? ? "UNKNOWN" : names.join("|")
    end

    private

    # @rbs (Grammar::Symbol sym) -> Integer
    def compute_terminal_context(sym)
      name = sym.id.s_value

      # Remove surrounding quotes for single-char tokens like "'{'" or "'('"
      bare = name.gsub(/\A["']|["']\z/, "")

      case bare
      # Keywords that start expressions
      when /\Akeyword_(?:if|unless|while|until|case|for|begin|do)\z/,
           /\Akeyword_(?:return|break|next|yield|super|defined)\z/,
           /\Akeyword_(?:class|module)\z/,
           /\Akeyword_(?:not|and|or|in)\z/,
           /\Akeyword_(?:then|else|elsif|when|ensure|rescue)\z/
        BEG

      # def keyword → next token is method name
      when /\Akeyword_def\z/
        ENDFN

      # end keyword
      when /\Akeyword_end\z/
        END_

      # Dot-like tokens
      when /\AtDOT\z/, /\AtCOLON2\z/, /\AtANDDOT\z/,
           /\A\.\z/, /\A::\z/
        DOT

      # Open brackets/parens → beginning of new expression
      when /\AtLPAREN\z/, /\AtLBRACK\z/, /\AtLBRACE\z/,
           /\AtLPAREN_ARG\z/, /\AtLBRACE_ARG\z/,
           /\A[\(\{\[]\z/
        BEG

      # Close brackets/parens → end of expression
      when /\AtRPAREN\z/, /\AtRBRACK\z/, /\AtRBRACE\z/,
           /\A[\)\}\]]\z/
        END_

      # Assignment operators → beginning of new expression
      when /\AtOP_ASGN\z/, /\A=\z/
        BEG

      # Binary/unary operators → beginning of new expression
      when /\AtPLUS\z/, /\AtMINUS\z/, /\AtSTAR\z/, /\AtDSTAR\z/,
           /\AtAMPER\z/, /\AtPIPE\z/, /\AtCARET\z/, /\AtTILDE\z/,
           /\AtBANG\z/, /\AtPERCENT\z/,
           /\AtLSHFT\z/, /\AtRSHFT\z/,
           /\AtCMP\z/, /\AtEQ\z/, /\AtEQQ\z/, /\AtNEQ\z/,
           /\AtMATCH\z/, /\AtNMATCH\z/,
           /\AtGEQ\z/, /\AtLEQ\z/, /\AtGT\z/, /\AtLT\z/,
           /\AtANDOP\z/, /\AtOROP\z/,
           /\A[+\-*\/%^|&<>!~?]\z/,
           /\AtDOT2\z/, /\AtDOT3\z/, /\AtBDOT2\z/, /\AtBDOT3\z/
        BEG

      # Comma, semicolon → beginning of next element
      when /\A[,;]\z/, /\AtCOMMA\z/, /\AtSEMI\z/
        BEG

      # Colon (for symbols, ternary, or hash) → beginning
      when /\AtCOLON\z/, /\AtSYMBEG\z/, /\AtCOLON3\z/, /\A:\z/
        BEG

      # Arrow, association operators
      when /\AtASSOC\z/, /\AtLAMBDA\z/, /\AtLAMBEG\z/
        BEG

      # String/symbol/regex begin
      when /\AtSTRING_BEG\z/, /\AtXSTRING_BEG\z/, /\AtREGEXP_BEG\z/,
           /\AtSYMBEG\z/, /\AtBACK_REF2\z/
        BEG

      # Identifiers → command argument position (method call with args)
      when /\AtIDENTIFIER\z/, /\AtFID\z/
        CMDARG

      # Constants
      when /\AtCONSTANT\z/
        CMDARG

      # Literals → end of expression
      when /\AtINTEGER\z/, /\AtFLOAT\z/, /\AtRATIONAL\z/, /\AtIMAGINARY\z/,
           /\AtCHAR\z/,
           /\AtSTRING_END\z/, /\AtREGEXP_END\z/, /\AtLABEL_END\z/,
           /\AtSYMBOL\z/, /\AtSTRING\z/,
           /\AtSELF\z/, /\AtNIL\z/, /\AtTRUE\z/, /\AtFALSE\z/,
           /\A__FILE__\z/, /\A__LINE__\z/, /\A__ENCODING__\z/
        END_

      # Unary operators (prefix) → BEG
      when /\AtUPLUS\z/, /\AtUMINUS\z/, /\AtUMINUS_NUM\z/
        BEG

      # Newline, EOF → BEG (start of next statement)
      when /\AtNL\z/, /\AtEOF\z/, /\\n/
        BEG

      # Label
      when /\AtLABEL\z/
        BEG

      # Modifier keywords → END (after expression)
      when /\Amodifier_/
        END_

      else
        0  # Unknown
      end
    end

    # @rbs (Grammar::Symbol sym) -> Integer
    def compute_nonterminal_context(sym)
      name = sym.id.s_value

      case name
      # Expression-like nonterminals → after reduction, we're at END
      when /\bexpr\b/, /\barg\b/, /\bprimary\b/, /\bliteral\b/,
           /\bvar_ref\b/, /\bvar_lhs\b/, /\bbackref\b/,
           /\bsuperclass\b/, /\bsingleton\b/
        END_

      # Method/function name → ENDFN
      when /\bfname\b/, /\bfsym\b/, /\bfitem\b/,
           /\bf_bad_arg\b/, /\bop\b/, /\breswords\b/
        ENDFN

      # Argument lists, parameters → various
      when /\bf_arglist\b/, /\bf_paren_args\b/, /\bf_args\b/
        BEG  # After arg list, body begins

      when /\bcall_args\b/, /\bopt_call_args\b/, /\bparen_args\b/
        END_

      # Statement-level → END
      when /\bstmt\b/, /\bstmts\b/, /\bcompstmt\b/, /\bbodystmt\b/,
           /\btop_compstmt\b/
        END_

      # Dot-like
      when /\bdot_or_colon\b/
        DOT

      # Terms, terminators
      when /\bterms?\b/, /\bopt_terms\b/, /\bnone\b/
        BEG

      # Block-related
      when /\bbrace_body\b/, /\bdo_body\b/, /\bk_end\b/
        END_

      # Command → CMDARG context
      when /\bcommand\b/, /\bcommand_call\b/, /\bfcall\b/, /\boperation\b/
        CMDARG

      # Method call result → END
      when /\bmethod_call\b/
        END_

      else
        0  # Unknown
      end
    end
  end
end
