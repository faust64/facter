#--
# Copyright 2006 Luke Kanies <luke@madstop.com>
# 
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
# 
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
# 
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
# 
#--

module Facter
    require 'facter/fact'

    include Comparable
    include Enumerable

    FACTERVERSION = '1.3.8'
	# = Facter
    # Functions as a hash of 'facts' you might care about about your
    # system, such as mac address, IP address, Video card, etc.
    # returns them dynamically

	# == Synopsis
	#
    # Generally, treat <tt>Facter</tt> as a hash:
    # == Example
    # require 'facter'
    # puts Facter['operatingsystem']
    #


    @@facts = Hash.new { |hash, key|
        key = key.to_s.downcase.intern
        if hash.include?(key)
            hash[key]
        else
            nil
        end
    }
    GREEN = "[0;32m"
    RESET = "[0m"
    @@debug = 0

	# module methods

    # Return the version of the library.
    def self.version
        return FACTERVERSION
    end

    # Add some debugging
    def self.debug(string)
        if string.nil?
            return
        end
        if @@debug != 0
            puts GREEN + string + RESET
        end
    end

    # Return a fact object by name.  If you use this, you still have to call
    # 'value' on it to retrieve the actual value.
    def self.[](name)
        @@facts[name]
    end

    # Add a resolution mechanism for a named fact.  This does not distinguish
    # between adding a new fact and adding a new way to resolve a fact.
    def self.add(name, options = {}, &block)
        unless fact = @@facts[name]
            fact = Facter::Fact.new(name, options)
            @@facts[name] = fact
        end

        unless block
            return fact
        end

        fact.add(&block)

        return fact
    end

    class << self
        include Enumerable
        # Iterate across all of the facts.
        def each
            @@facts.each { |name,fact|
                value = fact.value
                if ! value.nil?
                    yield name.to_s, fact.value
                end
            }
        end

        # Allow users to call fact names directly on the Facter class,
        # either retrieving the value or comparing it to an existing value.
        def method_missing(name, *args)
            question = false
            if name.to_s =~ /\?$/
                question = true
                name = name.to_s.sub(/\?$/,'')
            end

            if fact = @@facts[name]
                if question
                    value = fact.value.downcase
                    args.each do |arg|
                        if arg.to_s.downcase == value
                            return true
                        end
                    end

                    # If we got this far, there was no match.
                    return false
                else
                    return fact.value
                end
            else
                # Else, fail like a normal missing method.
                raise NoMethodError, "Could not find fact '%s'" % name
            end
        end
    end

    # Clear all facts.  Mostly used for testing.
    def self.clear
        Facter.flush
        Facter.reset
    end

	# Set debugging on or off.
	def self.debugging(bit)
		if bit
            case bit
            when TrueClass: @@debug = 1
            when FalseClass: @@debug = 0
            when Fixnum: 
                if bit > 0
                    @@debug = 1
                else
                    @@debug = 0
                end
            when String:
                if bit.downcase == 'off'
                    @@debug = 0
                else
                    @@debug = 1
                end
            else
                @@debug = 0
            end
		else
			@@debug = 0
		end
	end

    # Flush all cached values.
    def self.flush
        @@facts.each { |name, fact| fact.flush }
    end

    # Return a list of all of the facts.
    def self.list
        return @@facts.keys
    end

    # Remove them all.
    def self.reset
        @@facts.clear
    end

    # Return a hash of all of our facts.
    def self.to_hash
        @@facts.inject({}) do |h, ary|
            value = ary[1].value
            if ! value.nil?
                # For backwards compatibility, convert the fact name to a string.
                h[ary[0].to_s] = value
            end
            h
        end
    end

    def self.value(name)
        if fact = @@facts[name]
            fact.value
        else
            nil
        end
    end

    # Load all of the default facts
    def self.loadfacts
        Facter.add(:facterversion) do
            setcode { FACTERVERSION.to_s }
        end

        Facter.add(:rubyversion) do
            setcode { RUBY_VERSION.to_s }
        end

        Facter.add(:puppetversion) do
            setcode {
                begin
                    require 'puppet'
                    Puppet::PUPPETVERSION.to_s
                rescue LoadError
                    nil
                end
            }
        end

        Facter.add :rubysitedir do
            setcode do
                version = RUBY_VERSION.to_s.sub(/\.\d+$/, '')
                $:.find do |dir|
                    dir =~ /#{File.join("site_ruby", version)}$/
                end
            end
        end

        locals = []

        # Now find all our loadable facts
        factdirs = [] # All the places to check for facts
        
        # See if we can find any other facts in the regular Ruby lib
        # paths
        $:.each do |dir|
            fdir = File.join(dir, "facter")
            if FileTest.exists?(fdir) and FileTest.directory?(fdir)
                factdirs.push(fdir)
            end
        end
        # Also check anything in 'FACTERLIB'
        if ENV['FACTERLIB']
            ENV['FACTERLIB'].split(":").each do |fdir|
                factdirs.push(fdir)
            end
        end
        factdirs.each do |fdir|
            Dir.glob("#{fdir}/*.rb").each do |file|
                # Load here, rather than require, because otherwise
                # the facts won't get reloaded if someone calls
                # "loadfacts".  Really only important in testing, but,
                # well, it's important in testing.
                begin
                    load file
                rescue => detail
                    warn "Could not load %s: %s" %
                        [file, detail]
                end
            end
        end
        

        # Now try to get facts from the environment
        ENV.each do |name, value|
            if name =~ /^facter_?(\w+)$/i
                Facter.add($1) do
                    setcode { value }
                end
            end
        end
    end

    Facter.loadfacts
end
