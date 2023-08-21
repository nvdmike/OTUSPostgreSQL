set search_path = pract_functions, public;

create or replace function good_sum_mart_sum() returns trigger as $$
declare
  v_SalesQty integer;
  v_GoodId integer;
begin
  case TG_OP
    when 'INSERT' then
      v_SalesQty = new.sales_qty;
      v_GoodId = new.good_id; 
    when 'UPDATE' then
      v_SalesQty = new.sales_qty - old.sales_qty;
      v_GoodId = old.good_id;
    when 'DELETE' then
      v_SalesQty = 0 - old.sales_qty;
      v_GoodId = old.good_id;
  end case;
  insert into good_sum_mart(good_name, sum_sale) select good_name, good_price * v_SalesQty from goods where goods_id = v_GoodId
  on conflict (good_name) do update set sum_sale = good_sum_mart.sum_sale + excluded.sum_sale where good_sum_mart.good_name = excluded.good_name;
  return null;
end;
$$ language plpgsql;