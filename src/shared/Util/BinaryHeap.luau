--[[
	BinaryHeap
	Minimal min-heap keyed by numeric priority (used by FlowField's Dijkstra).
]]

local BinaryHeap = {}
BinaryHeap.__index = BinaryHeap

export type Heap = typeof(setmetatable({} :: { items: { any }, prio: { number }, size: number }, BinaryHeap))

function BinaryHeap.new(): Heap
	return setmetatable({ items = {}, prio = {}, size = 0 }, BinaryHeap)
end

function BinaryHeap.Push(self: Heap, item: any, priority: number)
	local items, prio = self.items, self.prio
	local i = self.size + 1
	self.size = i
	items[i] = item
	prio[i] = priority
	while i > 1 do
		local parent = i // 2
		if prio[parent] <= prio[i] then
			break
		end
		items[i], items[parent] = items[parent], items[i]
		prio[i], prio[parent] = prio[parent], prio[i]
		i = parent
	end
end

function BinaryHeap.Pop(self: Heap): (any, number)
	local items, prio = self.items, self.prio
	local size = self.size
	if size == 0 then
		return nil, math.huge
	end
	local topItem, topPrio = items[1], prio[1]
	items[1], prio[1] = items[size], prio[size]
	items[size], prio[size] = nil, nil
	size -= 1
	self.size = size
	local i = 1
	while true do
		local l = i * 2
		local r = l + 1
		local smallest = i
		if l <= size and prio[l] < prio[smallest] then
			smallest = l
		end
		if r <= size and prio[r] < prio[smallest] then
			smallest = r
		end
		if smallest == i then
			break
		end
		items[i], items[smallest] = items[smallest], items[i]
		prio[i], prio[smallest] = prio[smallest], prio[i]
		i = smallest
	end
	return topItem, topPrio
end

function BinaryHeap.IsEmpty(self: Heap): boolean
	return self.size == 0
end

return BinaryHeap
