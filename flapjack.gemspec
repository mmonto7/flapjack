Gem::Specification.new do |s|
  s.name = 'flapjack'
  s.version = '0.3.2'
  s.date = '2009-05-26'
  
  s.summary = "a scalable and distributed monitoring system"
  s.description = "Flapjack is highly scalable and distributed monitoring system. It understands the Nagios plugin format, and can easily be scaled from 1 server to 1000."
  
  s.authors = ['Lindsay Holmwood']
  s.email = 'lindsay@holmwood.id.au'
  s.homepage = 'http://flapjack-project.com'
  s.has_rdoc = false

  s.add_dependency('daemons', '>= 1.0.10')
  s.add_dependency('beanstalk-client', '>= 1.0.2')
  s.add_dependency('log4r', '>= 1.0.5')
  s.add_dependency('xmpp4r-simple', '>= 0.8.8')
  s.add_dependency('mailfactory', '>= 1.4.0')
 
  s.bindir = "bin"
  s.executables = `git ls-files bin/*`.split
  s.files = `git ls-files`.split.grep(/^[^\.gitignore|^spec\/]/)
end


