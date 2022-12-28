# Better Outputs
## Objective
- Find better and more informative output
- Have correct timer output
- Single entry point for output in the script

## Design
- think of a data structure that I can use to determine output
- I need to persist previous pomodoro records, so support that too
- Strike through and color support for tasks done and task in progress, and
  cancelled tasks.


Workflow:
- on start, type out tasks I want to do
- list the tasks with a number on them e.g. 1 play game, 2 eat lunch, ...
- once done, I can mark them as done using d and the number of the item
- cross out tasks that are marked done.
- if I get a priority or change my plan, I mark a task as cancelled using c#.
- grey out cancelled items.
- add new tasks using a

Example:

```
Pomodoro 1
Add items: play game, eat lunch, read book

# above gets cleared and this is displayed
Pomodoro 1
Plan: 1 play game, 2 eat lunch, 3 read book

# After done with task 1 press d and get
Pomodoro 1
Plan: 1 play game, 2 eat lunch, 3 read book
Enter index to mark as done: 1

# This is displayed
Pomodoro 1
Plan: ~1 play game~, 2 eat lunch, 3 read book

# Similar workflow as c
# a has a similar workflow as the initial prompt but adds to the list
```
