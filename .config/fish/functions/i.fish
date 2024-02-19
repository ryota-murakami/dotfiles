function i --wraps='SHELL=(which bash) interpreter -y' --description 'alias i=SHELL=(which bash) interpreter -y'
  SHELL=(which bash) interpreter -y $argv
end
