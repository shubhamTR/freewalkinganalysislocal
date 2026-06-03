function val = map_or_default(m, key)
% MAP_OR_DEFAULT  Look up key in containers.Map; return key itself if not found.
    if m.isKey(key)
        val = m(key);
    else
        val = key;
    end
end
