set ts 0

proc calcforces { } { 
  global ts
  print "TCLFORCES $ts  ([getstep])"
  incr ts
  return
}
