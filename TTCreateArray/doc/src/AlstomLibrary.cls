\NeedsTeXFormat{LaTeX2e}
 
\ProvidesClass{AlstomLibrary}[2011/07/11 Librairie Alstom, V1.0]
 
% classe de base
 
\LoadClass[11pt]{scrreprt} % use larger type; default would be 10pt

% extensions

\RequirePackage[utf8]{inputenc} % set input encoding (not needed with XeLaTeX)
\RequirePackage{booktabs,longtable} % for much better looking tables
\RequirePackage[french]{varioref}
\RequirePackage{hyperref}
\RequirePackage[top=3cm, bottom=3cm,a4paper]{geometry}
\RequirePackage[frenchb]{babel}
\RequirePackage{graphicx} % support the \includegraphics command and options
\RequirePackage[parfill]{parskip} % Activate to begin paragraphs with an empty line rather than an indent
\RequirePackage{tikz-timing}

\setcounter{tocdepth}{3}

\tikzset{timing/slope=0,timing/coldist=2pt, timing/name/.style={font=\sffamily\scriptsize}}

         
\definecolor{fgblue}{rgb}{0 ,0 ,0.6}%
\definecolor{fgred}{rgb}{0.6 ,0 ,0}%

% commandes personnelles

\reversemarginpar
\renewcommand{\arraystretch}{1.3} % more space between rows

\newcommand{\reqtext}{EXIGENCE\_}
\newcommand{\TRUE}{\emph{VRAI}}
\newcommand{\FALSE}{\emph{FAUX}}


\newcommand{\variable}[1]{\texttt{#1}}
\newcommand{\novariable}[1]{$\overline{\mbox{\variable{#1}}}$}
\newcommand{\exigence}[1]{\marginpar{\texttt{\scriptsize{\reqtext#1}}}}
\newcommand{\modulename}[1]{\texttt{#1}}
\newcommand{\folding}[1]{\\ \textit{(Section : \texttt{#1})}}