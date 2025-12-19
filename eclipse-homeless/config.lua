Config = {}

-- Homeless NPC (talk here to register + welfare)
Config.HomelessNPC = {
    label = "Homeless Outreach Worker",
    model = 'a_m_m_hillbilly_02',
    coords = vector4(-61.98, -1217.95, 28.7, 276.56), -- CHANGE THIS
    targetRadius = 2.0
}

-- Metadata key used on the QB player
Config.HomelessMetaKey = 'isHomeless'

-- Welfare
Config.Welfare = {
    enabled = true,
    amount = 600,
    account = 'cash', -- 'cash' or 'bank'
    oncePerRealDay = true
}

-- Squatting / ownership
Config.MinutesToOwn = 180 -- minutes required INSIDE the warehouse
Config.TickMinutes = 1    -- accrual tick in minutes

Config.Warehouses = {
    ["docks_warehouse"] = {
        label = "Old Docks Warehouse",
        entry = vector4(1197.13, -3253.46, 7.1, 271.4), -- CHANGE THIS
        interior = vector4(997.33, -3200.61, -36.39, 270.0),
        exit = vector4(1088.65, -3099.33, -39.00, 90.0),
        stash = vector3(1017.24, -3198.13, -38.99),
    }
}

Config.Stash = {
    slots = 50,
    weight = 200000
}

-- Optional: police override
Config.PoliceOverride = true
Config.PoliceJobNames = { ["police"] = true, ["sheriff"] = true }
