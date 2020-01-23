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

module Async
	module Container
		class Group
			def initialize
				@running = {}
				
				# This queue allows us to wait for processes to complete, without spawning new processes as a result.
				@queue = nil
			end
			
			def any?
				@running.any?
			end
			
			def empty?
				@running.empty?
			end
			
			# This method sleeps for the specified duration, then 
			def sleep(duration)
				self.resume
				self.suspend
				
				::Kernel::sleep(duration)
				
				# This waits for any process to exit.
				while self.wait_one(false)
				end
			end
			
			def wait
				self.resume
				
				while self.any?
					self.wait_one
				end
			end
			
			def stop(timeout = 1)
				# Handle legacy `graceful = true` argument:
				if timeout == true
					timeout = 1
				end
				
				self.interrupt
				self.sleep(timeout)
			ensure
				self.close
			end
			
			def close
				self.terminate
				self.interrupt_all
			end
			
			protected
			
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
			
			def interrupt_all
				while self.any?
					self.wait_one do |fiber, status|
						begin
							# This causes the waiting fiber to `raise Interrupt`:
							fiber.resume(nil)
						rescue Interrupt
							# Graceful exit.
						end
					end
				end
			end
			
			public
			
			def wait_for(value)
				@running[value] = Fiber.current
				
				# Return process status:
				if result = Fiber.yield
					return result
				else
					raise Interrupt
				end
			end
		end
	end
end