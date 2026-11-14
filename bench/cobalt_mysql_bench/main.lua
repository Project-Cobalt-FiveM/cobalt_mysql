CreateThread(function()
	MySQL.ready.await()
	Wait(1000)

	for _, step in ipairs(Bench.steps) do
		print(('BENCH step | %s'):format(step.name))

		local ok <const>, err <const> = pcall(step.run)
		if not ok then print(('BENCH step failed | %s | %s'):format(step.name, err)) end
	end

	print('BENCH DONE')
end)
