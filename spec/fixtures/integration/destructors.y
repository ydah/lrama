%{

#define YYDEBUG 1

#include <stdio.h>
#include "printers.h"
#include "printers-lexer.h"

static int yyerror(YYLTYPE *loc, const char *str);

%}

%union {
    int val1;
    int val2;
    int val3;
}

%token <val1> NUM
%type <val2> expr2
%type <val3> expr
%left '+' '-'
%left '*' '/'

%destructor {
    printf("destructor for val1: %d\n", $$);
} <val1> // printer for TAG

%destructor {
    printf("destructor for val2: %d\n", $$);
} <val2>

%destructor {
    printf("destructor for expr: %d\n", $$);
} expr // printer for symbol

%%

program : /* empty */
     | expr { printf("=> %d\n", $1); }
     | expr2 '+'
     ;

expr2: '+' NUM { $$ = $2; }
     ;

expr : NUM
     | expr '+' expr { $$ = $1 + $3; }
     | expr '-' expr { $$ = $1 - $3; }
     | expr '*' expr { $$ = $1 * $3; }
     | expr '/' expr { $$ = $1 / $3; }
     | '(' expr ')'  { $$ = $2; }
     ;

%%

static int yyerror(YYLTYPE *loc, const char *str) {
    fprintf(stderr, "parse error: %s\n", str);
    return 0;
}

int main(int argc, char *argv[]) {
    yydebug = 1;

    if (argc == 2) {
        yy_scan_string(argv[1]);
    }

    if (yyparse()) {
        fprintf(stderr, "syntax error\n");
        return 1;
    }
    return 0;
}
