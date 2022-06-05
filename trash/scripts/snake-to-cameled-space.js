#!/usr/bin/env node

/*
Log at making proccess

> 'code-piece-of-complete-guide-to-react-rendering-behavior'.split('-')
[
  'code',     'piece',
  'of',       'complete',
  'guide',    'to',
  'react',    'rendering',
  'behavior'
]
> 'code-piece-of-complete-guide-to-react-rendering-behavior'.split('-').map(s => s.charAt(0).toUpperCase())
[
  'C', 'P', 'O',
  'C', 'G', 'T',
  'R', 'R', 'B'
]
> 'code-piece-of-complete-guide-to-react-rendering-behavior'.split('-').map(s => "${s.charAt(0).toUpperCase()}" + s.slice(1))
[
  '${s.charAt(0).toUpperCase()}ode',
  '${s.charAt(0).toUpperCase()}iece',
  '${s.charAt(0).toUpperCase()}f',
  '${s.charAt(0).toUpperCase()}omplete',
  '${s.charAt(0).toUpperCase()}uide',
  '${s.charAt(0).toUpperCase()}o',
  '${s.charAt(0).toUpperCase()}eact',
  '${s.charAt(0).toUpperCase()}endering',
  '${s.charAt(0).toUpperCase()}ehavior'
]
> 'code-piece-of-complete-guide-to-react-rendering-behavior'.split('-').map(s => (s.charAt(0).toUpperCase() + s.slice(1)))
[
  'Code',     'Piece',
  'Of',       'Complete',
  'Guide',    'To',
  'React',    'Rendering',
  'Behavior'
]
> 'code-piece-of-complete-guide-to-react-rendering-behavior'.split('-').map(s => (s.charAt(0).toUpperCase() + s.slice(1))).concat(' ')
[
  'Code',     'Piece',
  'Of',       'Complete',
  'Guide',    'To',
  'React',    'Rendering',
  'Behavior', ' '
]
> 'code-piece-of-complete-guide-to-react-rendering-behavior'.split('-').map(s => (s.charAt(0).toUpperCase() + s.slice(1))).join(' ')
'Code Piece Of Complete Guide To React Rendering Behavior'
>
*/

let str = process.argv[2]

console.log(str.split('-').map(s => (s.charAt(0).toUpperCase() + s.slice(1))).join(' '))
