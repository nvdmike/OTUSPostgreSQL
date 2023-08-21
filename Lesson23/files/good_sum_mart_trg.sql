set search_path = pract_functions, public;

create trigger good_sum_mart_trg
after insert or update or delete on sales
for each row execute function good_sum_mart_sum();