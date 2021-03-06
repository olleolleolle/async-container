# frozen_string_literal: true

# Copyright, 2017, by Samuel G. D. Williams. <http://www.codeotaku.com>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'fiber'

require 'async/clock'

require_relative 'error'

module Async
	module Container
		# Manages a group of running processes.
		class Group
			def initialize
				@running = {}
				
				# This queue allows us to wait for processes to complete, without spawning new processes as a result.
				@queue = nil
			end
			
			# @attribute [Hash<IO, Fiber>] the running tasks, indexed by IO.
			attr :running
			
			def running?
				@running.any?
			end
			
			def any?
				@running.any?
			end
			
			def empty?
				@running.empty?
			end
			
			# This method sleeps for at most the specified duration.
			def sleep(duration)
				self.resume
				self.suspend
				
				self.wait_for_children(duration)
			end
			
			def wait
				self.resume
				
				while self.running?
					self.wait_for_children
				end
			end
			
			def interrupt
				@running.each_value do |fiber|
					fiber.resume(Interrupt)
				end
			end
			
			def terminate
				@running.each_value do |fiber|
					fiber.resume(Terminate)
				end
			end
			
			def stop(timeout = 1)
				# Handle legacy `graceful = true` argument:
				if timeout
					start_time = Async::Clock.now
					
					# Use a default timeout if not specified:
					timeout = 1 if timeout == true
					
					self.interrupt
					
					while self.any?
						duration = Async::Clock.now - start_time
						remaining = timeout - duration
						
						if remaining >= 0
							self.wait_for_children(duration)
						else
							self.wait_for_children(0)
							break
						end
					end
				end
				
				# Timeout can also be `graceful = false`:
				if timeout
					self.interrupt
					self.sleep(timeout)
				end
				
				self.wait_for_children(duration)
				
				# Terminate all children:
				self.terminate
				
				# Wait for all children to exit:
				self.wait
			end
			
			def wait_for(channel)
				io = channel.in
				
				@running[io] = Fiber.current
				
				while @running.key?(io)
					result = Fiber.yield
					
					if result == Interrupt
						channel.interrupt!
					elsif result == Terminate
						channel.terminate!
					elsif message = channel.receive
						yield message
					else
						return channel.wait
					end
				end
			ensure
				@running.delete(io)
			end
			
			protected
			
			def wait_for_children(duration = nil)
				if !@running.empty?
					readable, _, _ = ::IO.select(@running.keys, nil, nil, duration)
					
					readable&.each do |io|
						@running[io].resume
					end
				end
			end
			
			def yield
				if @queue
					fiber = Fiber.current
					
					@queue << fiber
					Fiber.yield
				end
			end
			
			def suspend
				@queue ||= []
			end
			
			def resume
				if @queue
					queue = @queue
					@queue = nil
					
					queue.each(&:resume)
				end
			end
		end
	end
end
