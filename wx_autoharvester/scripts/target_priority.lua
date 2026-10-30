local priority = {}
for _, category in ipairs(require("target_categories")) do
    for _, item in ipairs(category.items) do
        priority[#priority + 1] = item.key
    end
end
return priority
