-- [tbd]
-- 
-- 
--
-- 
--
--
-- v0.4 imminent gloom

-- setup
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

local save_on_exit = true

g = grid.connect()

tab = require("tabutil")

nb = include("nb/lib/nb")

local t = {} -- hold tracks
local p = {  -- hold patterns
	{{},{},{},{}},
	{{},{},{},{}},
	{{},{},{},{}},
	{{},{},{},{}},
}
local p_step = {
	{{},{},{},{}},
	{{},{},{},{}},
	{{},{},{},{}},
	{{},{},{},{}},
}
local p_state = {"empty", "empty", "empty", "empty"}
local p_current = 1

local edit_step = {1, 1}

local trig = {false, false, false, false}
local trig_index = {1, 1, 1, 1}
local mute = {false, false, false, false}
local rec = {true, true, true, true}
local erase = false
local random = false
local shift_1 = false
local shift_2 = false

local seq_play = true
local seq_reset = false

local loop_buff = {{},{},{},{}}
local fill_buff = {}
local shift_buff_1 = {}
local shift_buff_2 = {}

local fill_rate = {1, 2, 4, 8, 16, 32}
local probably = {1/2000, 1/1000, 1/500}

local ppqn = 96

local fps = 32
local frame = 1
local frame_anim = 1
local frame_steps = 8

local k1_held = false

local crow_trig = true

-- Track class
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

track = {}
track.__index = track
track.substeps = ppqn / 4
local num_tracks = 0

function track.new()
   local sequence = setmetatable({}, track)
   
   num_tracks = num_tracks + 1
   sequence.number = num_tracks
   
   sequence.voice = "nb_voice_" .. num_tracks
   nb:add_param(tostring(sequence.voice), "track " .. num_tracks .. ":" )
   
   sequence.index = 1
   sequence.step = 1
   sequence.substep = 0

   sequence.loop_start = 1
   sequence.loop_end = 16

   sequence.note = sequence.number
   sequence.velocity = 1
   sequence.duration = 1

   sequence.data = {}
   for n = 1, 16 * sequence.substeps do
      sequence.data[n] = 0
   end
   
   sequence.data_step = {}
   for n = 1, 16 do
      sequence.data_step[n] = 0
   end

   return sequence
end

function track:retreat() -- decrement substeps and steps inside loop_start and loop_end
   self.substep = self.substep - 1

   if self.substep < 1 then
      self.substep = 24
      self.step = self.step - 1
   end

   if self.step > self.loop_end then
      self.step = self.loop_end
   end

   if self.step < self.loop_start then
      self.step = self.loop_end
   end

   self.index = math.floor((self.step - 1) * self.substeps + self.substep)
end

function track:advance() -- increment substeps and steps inside loop_start and loop_end
   self.substep = self.substep + 1

   if self.substep > self.substeps then
      self.substep = 1
      self.step = self.step + 1
   end

   if self.step < self.loop_start then
      self.step = self.loop_start
   end

   if self.step > self.loop_end then
      self.step = self.loop_start
   end
	
   self.index = math.floor((self.step - 1) * self.substeps + self.substep)
end

function track:write(val, index) -- writes val to index OR value to current possition OR inverts current possition
   index = index or self.index
   val = val or self.data[index] % 2
   self.data[index] = val

   if val == 1 then
      self.data_step[self:index_2_step(index)] = 1
   else
      if not self:get_step(self:index_2_step(index)) then 
         self.data_step[self:index_2_step(index)] = 0   
      end
   end
end

function track:reset(step) -- resets to step OR start of loop
   step = step or 1
   self.step = util.clamp(step, self.loop_start, self.loop_end)
   self.substep = 0
   self.index = math.floor((self.loop_start - 1) * self.substeps + 1)
end

function track:loop(l1, l2) -- sets loop points, args in any order
   l1 = l1 or 1
   l2 = l2 or 16
   self.loop_start = math.min(l1, l2)
   self.loop_end = math.max(l1, l2)   
end

function track:clear_sequence()
   for n = 1, 16 * self.substeps do 
      self.data[n] = 0
   end

   for n = 1, 16 do
      self.data_step[n] = 0
   end
end

function track:clear_step(step) -- clear step OR clear current step
   step = step or self.step

   for n = self:step_2_index(step), self:step_2_index(step) + 23 do
      self.data[n] = 0
   end   

   self.data_step[step] = 0
end

function track:hit() -- trigger drum hit
   player = params:lookup_param(self.voice):get_player()
   player:play_note(self.note, self.velocity, self.duration)
	
	if crow_trig then
		crow.output[n].action = "pulse()"
		crow.output[n]()
	end
end

function track:step_2_index(step) -- converts step# to index
   return math.floor((step - 1) * self.substeps + 1)
end

function track:index_2_step(index) -- converts index to step#
   return math.floor((index - 1) / 24) + 1
end

function track:get_step(step) -- cheks if step has active substeps OR current step has active
   step = step or self.step
   local sum = 0

   for substep = 1, self.substeps do
      if self.data[(step - 1) * self.substeps + substep] == 1 then
         sum = sum + 1
      end
   end

   if sum == 0 then return false else return true end
end

-- utility functions
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

local function g_buffer(buff, val, z) -- tracks held keys in order
   if z == 1 then
      -- add all held fills to a table in order
      table.insert(buff, val)
   else
      -- remove each step as it is released
      for i, v in pairs(buff) do
         if v == val then
            table.remove(buff, i)
         end
      end
   end
end

-- pattern, load
local function pattern_to_sequence(pattern)
	for track = 1, 4 do
		for index = 1, ppqn * 4 do
			t[track].data[index] = p[pattern][track][index]
		end

		for step = 1, 16 do
			t[track].data_step[step] = p_step[pattern][track][step]
		end
	end

	p_current = pattern
end

-- pattern, save
local function sequence_to_pattern(pattern)
	for track = 1, 4 do
		for index = 1, ppqn * 4 do
			p[pattern][track][index] = t[track].data[index]
		end

		for step = 1, 16 do
			p_step[pattern][track][step] = t[track].data_step[step]
		end
	end

	p_state[pattern] = "full"
end

-- pattern, clear
local function pattern_clear(pattern)
	for track = 1, 4 do
		for index = 1, ppqn * 4 do
			p[pattern][track][index] = 0
		end

		for step = 1, 16 do
			p_step[pattern][track][step] = 0
		end
	end

	p_state[pattern] = "empty"
end

-- init
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function init()
   
   nb.voice_count = 4

   for n = 1, 4 do t[n] = track.new() end
   
   nb:add_player_params()
   
	for pattern = 1, 4 do
		pattern_clear(pattern)
	end

   clk_main = clock.run(c_main)
   clk_fps = clock.run(c_fps)

   if save_on_exit then
      params:read("/home/we/dust/data/tr/tr_4_state.pset")
   end

   -- params
   -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
	params:add_option("crow", "crow triggers", {"on", "off"}, 1)
	params:set_action("crow", function(x) if x == 1 then crow_trig = true else crow_trig = false end end)
   -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
	


   g_redraw()

end

-- clock
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function c_main()
   while true do
      clock.sync(1/ppqn)
      
      for n = 1, 4 do
         t[n]:advance()
         c_main_core(n)
      end
      
   end
end

function c_main_core(n)
   if erase and trig[n] then
      t[n]:write(0)
   end
         
   if fill and trig[n] then
      local rate = ppqn / 4 / fill_rate[util.clamp(#fill_buff, 0, #fill_rate)]

      if ((t[n].substep - 1) % rate) + 1 == ((trig_index[n] - 1) % rate) + 1 then
         if rec[n] then
            t[n]:write(1)
         end

         if not rec[n] and not mute[n] then
            t[n]:hit()                  
         end
      end
   end

   if t[n].data[t[n].index] == 1 and not mute[n] then
      t[n]:hit()
   end

   g_redraw()
end

function c_fps()
   while true do
      clock.sleep(1/fps)

      frame = frame + 1

      if frame > fps then
         frame = 1
      end

		frame_anim = util.clamp(math.floor(frame_steps / fps * frame), 1, frame_steps)
		frame_rnd = math.random(frame_steps)

      g_redraw()
   end
end


-- grid: keys
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function g.key(x, y, z)
   
   local row = y
   local col = x
   
   if z == 1 then key_down = true else key_down = false end

   -- sequence
   if row <= 4 then
      if z == 1 then
         
         edit_step = {x, y}

         if shift_1 and shift_2 then
            edit_step = {x, y}
         else
            if erase then
               t[row]:clear_step(col)
            else   
               if t[row]:get_step(col) then
                  t[row]:clear_step(col)
               else
                  t[row]:write(1, t[row]:step_2_index(col))
               end
            end
         end
      end
   end
   
   -- rec
   if row == 5 and col <= 4 then
      if z == 1 then
         if rec[col] then
            rec[col] = false
         else
            rec[col] = true
         end
      end   
   end
   
   -- mutes
   if row == 6 and col <= 4 then
      if z == 1 then
         if mute[col] then
            mute[col] = false
         else
            mute[col] = true
         end
      end
   end   

   -- triggers
   if row >= 7 and col <= 4 then
      if z == 1 then
         edit_step = {t[col].step, col}
         trig_index[col] = t[col].substep
         trig[col] = true
      end

      if z == 0 then
         trig[col] = false
         trig_index[col] = 1
      end
      
      if erase then
         t[col]:write(0)
      end

      if not mute[col] and not erase then
         if z == 1 and rec[col] then
            t[col]:write(1)
            t[col]:hit()
         end
         
         if z == 1 and not rec[col] then
            t[col]:hit()
         end
      end

   end
   
   -- shift 1
   if row == 8 and col >=6 and col <=8 then
      g_buffer(shift_buff_1, col, z)
      if #shift_buff_1 > 0 then shift_1 = true else shift_1 = false end
   end
   
   -- shift 2 
   if row == 8 and col >=9 and col <=11 then
      g_buffer(shift_buff_2, col, z)

      if #shift_buff_2 > 0 then shift_2 = true else shift_2 = false end

      if erase then
         for n = 1, 4 do
            t[n]:clear_sequence()
         end
      end
   end
   
	-- patterns
	if row == 5 and col >= 13 then
		local pattern = col - 12

		if z == 1 then
			if erase then 	
				pattern_clear(pattern)
			elseif shift_2 then
				sequence_to_pattern(pattern)
			else
				pattern_to_sequence(pattern)
			end
		end
	end

   -- erase
   if row == 6 and col == 16 then
      if z == 1 then erase = true else erase = false end	
   end

	if erase and shift_2 then
		for n = 1, 4 do
			t[n]:clear_sequence()
		end
	end
   
   -- random
   if row == 6 and col == 15 then
      if z == 1 then random = true else random = false end
   end

	if random and shift_2 then
		for track = 1, 4 do
			if rec[track] then
				for index = 1, ppqn * 4 do

					if math.random() < probably[#shift_buff_2] then
						t[track].data[index] = (t[track].data[index] + 1) % 2

						if t[track]:get_step(t[track]:index_2_step(index)) then
							t[track].data_step[t[track]:index_2_step(index)] = 1
						else
							t[track].data_step[t[track]:index_2_step(index)] = 0
						end
					end
				end
			end
		end
	end
   
   -- reset
   if row == 6 and col == 14 then
      if z == 1 then seq_reset = true else seq_reset = false end
		
      if z == 1 then
         for n = 1, 4 do
            t[n]:reset()
         end
      end
   end
   
   -- play
   if row == 6 and col == 13 then
      if z == 1 then
         if seq_play then
            clock.cancel(clk_main)
            seq_play = false
         else
            clk_main = clock.run(c_main)
            seq_play = true
         end
      end
   end   

	-- fill
	if (row == 7 or row == 8) and col >= 13 then
		local col = ((row - 7) * 4) + col - 12 
		g_buffer(fill_buff, col, z)
		if #fill_buff > 0 then fill = true else fill = false end
	end      
	
   -- step edit
   if (row == 5 or row == 6 or row == 7) and (col >=5 and col <= 12) then
      if z == 1 then
         local track = edit_step[2]
         local step = t[track]:step_2_index(edit_step[1])
         local substep = (col - 4) + ((row - 5) * 8)

         if t[track].data[step + substep - 1] == 1 then
            t[track]:write(0, step + substep - 1)
         else
            t[track]:write(1, step + substep - 1)
         end
      end
   end

   g_redraw()
   
end

-- grid: "color" palette
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

local br_seq_b		=  5	-- sequence, background
local br_seq		=  8	-- sequence, looping steps
local br_seq_a		= 12	-- sequence, active steps
local br_seq_t		= 15	-- sequence, tracer
local br_sub		=  2	-- substeps, background
local br_sub_a		= 10	-- substeps, active steps
local br_sub_t		=  5	-- substeps, tracer
local br_rec		=  5	-- record
local br_m			=  8	-- mute
local br_t			=  4	-- triggers
local br_t_a		= 10	-- triggers, active steps
local br_t_h		= 15	--	triggers, held
local br_shift_1	=  5	-- shift 1
local br_shift_2	=  5	-- shift 2
local br_pat_e		=  0	-- pattern, empty
local br_pat_f		=  8	-- pattern, full
local br_pat_c		=  4	-- pattern, current, empty
local br_pat_c_f	= 12	-- pattern, current, full
local br_e			=  8	-- erase
local br_e_a		=  2	-- erase, active
local br_rnd		=  4	-- randomize
local br_rnd_a		=  2	-- randomize, active
local br_reset		=  8	-- reset
local br_reset_a	=  8	-- reset, active
local br_play		=  4	-- play
local br_play_a	= 10	-- play, active
local br_fill		=  4	-- fill
local br_fill_a	=  5	-- fill, active

-- grid: lights
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function g_redraw()

   g:all(0)

   -- loop
   for y = 1, 4 do
      for x = t[y].loop_start, t[y].loop_end do
         g:led(x, y, br_seq_b)
      end
   end

   -- sequence
   for y = 1, 4 do
      for x = 1, 16 do
         if t[y].data_step[x] == 1 then
            g:led(x, y, br_seq_a)
         end
      end
   end

   -- track controls
   for x = 1, 4 do
      -- rec
      if rec[x] then g:led(x, 5, br_rec + frame_anim) end
      if not rec[x] then g:led(x, 5, 0) end

      -- mute
      if mute[x] then g:led(x, 6, br_m) end
      if not mute[x] then g:led(x, 6, 0) end
   end

   -- triggers
   for x = 1, 4 do
      if trig[x] then
         g:led(x, 7, br_t_h)
         g:led(x, 8, br_t_h)
      end

      if not trig[x] then
         g:led(x, 7, br_t)
         g:led(x, 8, br_t)
      end
      
      if mute[x] then
         g:led(x, 7, 0)
         g:led(x, 8, 0)
      end

   -- flash active substep
      if t[x].data[t[x].index] == 1 and not mute[x] then
         g:led(x, 7, br_t_a)
         g:led(x, 8, br_t_a)
      end
   end

   -- shift_1
   for x = 6, 8 do
      if shift_1 then
         g:led(x, 8, br_shift_1 + #shift_buff_1 * 2)
      else
         g:led(x, 8, br_shift_1)
      end
   end
   
   -- shift_2
   for x = 9, 11 do
      if shift_2 then
         g:led(x, 8, br_shift_2 + #shift_buff_2 * 2)
      else
         g:led(x, 8, br_shift_2)
      end

      if erase then 
         g:led(x, 8, br_e_a)
		end
		if random then
         g:led(x, 8, br_rnd_a + frame_rnd)
      end
   end

	-- patterns
	for x = 1, 4 do
		if p_state[x] == "empty" then
			g:led(x + 12, 5, br_pat_e)
		end

		if p_state[x] == "full" then
			g:led(x + 12, 5, br_pat_f)
		end

		if p_current == x and p_state[x] == "empty" then
			g:led(x + 12, 5, br_pat_c)
		end	

		if p_current == x and p_state[x] == "full" then
			g:led(x + 12, 5, br_pat_c_f)
		end	
	end
	
	
   -- erase
   if erase then
      g:led(16, 6, br_e_a)
	elseif shift_2 then
		g:led(16, 6, br_e_a)
	else
      g:led(16, 6, br_e)
   end
	
   -- random
   if random then
      g:led(15, 6, br_rnd_a + frame_rnd)
	elseif shift_2 then
		g:led(15, 6, br_rnd_a + frame_rnd)
   else
      g:led(15, 6, br_rnd)
   end
	
   -- reset
   if seq_reset then
      g:led(14, 6, br_reset_a)
   else
      g:led(14, 6, br_reset)
   end
	
   -- play
   if seq_play then
      g:led(13, 6, br_play_a - frame_anim)
   else
      g:led(13, 6, br_play)
   end
	
	-- fill
	for x = 13, 16 do
		for y = 7, 8 do
			if fill then
				g:led(x, y, br_fill_a + #fill_buff)
			else
				g:led(x, y, br_fill)
			end
		end
	end

   -- step edit
   for y = 5, 7 do
      for x = 5, 12 do
         local substep = (x - 4) + ((y - 5) * 8)
         local track = edit_step[2]
         local step = t[track]:step_2_index(edit_step[1])

         if t[track].substep == substep and not seq_play then
            g:led(x, y, br_sub + br_sub_t)
         else
            g:led(x, y, br_sub)
         end

         if t[track].data[step + substep - 1] == 1 then
            if t[track].substep == substep and not seq_play then
               g:led(x, y, br_sub_a + br_sub_t)
            else
               g:led(x, y, br_sub_a)
            end
         end
      end
   end

   -- step edit: blink selection
	do
		local track = edit_step[2]
		local step = edit_step[1]
		local edit = t[track]

		if edit.data_step[step] == 0 then
			if edit.step < edit.loop_start or edit.step > edit.loop_end then
				g:led(step, track, br_seq - frame_anim)
			else
				g:led(step, track, br_seq_b - math.floor(frame_anim / 3))
			end
		end

		if edit.data_step[step] == 1 then
			g:led(step, track, br_seq_a - frame_anim)
		end
	end
   
   -- tracers
   for y = 1, 4 do
      if edit_step[2] == y and edit_step[1] == t[y].step then -- blink tracer on edited step
         g:led(t[y].step, y, br_seq_t - frame_anim)
      else 
         g:led(t[y].step, y, br_seq_t) -- normal bright tracer
      end
   end
      
   g:refresh()
end

-- norns: interaction
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function key(n, z)
   if n == 1 then
      if z == 1 then k1_held = true else k1_held = false end
   end
   
   if n == 2 then -- play
      if z == 1 then
         if seq_play then
            clock.cancel(clk_main)
            seq_play = false
         else
            clk_main = clock.run(c_main)
            seq_play = true
         end
      end
   end
   
   if n == 3 then -- reset
      if z == 1 then
         for n = 1, 4 do
            t[n]:reset()
         end
      end
   end
end

function enc(n, d)
   if n == 1 then
      params:delta("clock_tempo", d)
   end

   if n == 2 then
      d = util.clamp(d, -1, 1)
      local step = t[1].step + d
      
      if seq_play then
         edit_step[1] = ((edit_step[1] - 1 + d) % 16) + 1
      end
      
      if not seq_play then
         step = ((step - 1) % 16) + 1
         edit_step[1] = step

         for track = 1, 4 do
            t[track]:reset(step)
            t[track]:advance()
            c_main_core(track)
         end               
      end
   end

   if n == 3 then
      d = util.clamp(d, -1, 1)

      if not k1_held then
         if seq_play then
            edit_step[2] = ((edit_step[2] - 1 + d) % 4) + 1
         end

         if not seq_play then
            edit_step[1] = t[1].step

            for track = 1, 4 do
               if d > 0 then
                  t[track]:advance()
                  c_main_core(track)
               end
               if d < 0 then
                  t[track]:retreat()
                  c_main_core(track)
               end
            end
         end
      end

      if k1_held and not seq_play then
         edit_step[2] = ((edit_step[2] - 1 + d) % 4) + 1
      end
   end
end

-- norns: screen
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function redraw()
   screen.clear()
   screen.move(128, 8)
   screen.text_right(t[1].step .. "/")
   screen.move(128, 16)
   screen.text_right(t[1].substep .. "/")
   screen.move(128, 24)
   screen.text_right(t[1].index .. "/")
   screen.move(128, 32)
   screen.text_right(params:get("clock_tempo") .. " bpm")
	screen.update()
end

function refresh() redraw() end

-- tidy up before we go
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function cleanup()
   if save_on_exit then
      params:write("/home/we/dust/data/tr/tr_4_state.pset")
   end
end
